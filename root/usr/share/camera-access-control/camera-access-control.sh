#!/bin/sh
#
# camera-access-control.sh
# Controls LAN camera video transmission via nftables
#

. /lib/functions.sh

CHAIN="camera_access_control"
TABLE="inet fw4"
COUNTER_DIR="/tmp/cam-ctrl-counters"
LAST_ALERT_DIR="/tmp/cam-ctrl-alerts"

# Ensure temp directories exist
mkdir -p "$COUNTER_DIR" "$LAST_ALERT_DIR"

# Load UCI configuration
load_config() {
	config_load camera_access_control
}

# Get the local LAN subnet in CIDR notation
get_lan_subnet() {
	local lan_ip lan_prefix
	lan_ip=$(uci get network.lan.ipaddr 2>/dev/null)
	lan_prefix=$(uci get network.lan.netmask 2>/dev/null)

	if [ -z "$lan_ip" ]; then
		echo "192.168.0.0/16"
		return
	fi

	# Convert netmask to CIDR prefix using ipcalc or manual calculation
	if command -v ipcalc.sh >/dev/null 2>&1; then
		local cidr
		cidr=$(ipcalc.sh "$lan_ip" "$lan_prefix" 2>/dev/null | grep "^PREFIX=" | cut -d= -f2 | tr -d ' ')
		[ -n "$cidr" ] && echo "${lan_ip%.*}.0/${cidr}" && return
	fi

	# Fallback: use /24
	echo "${lan_ip%.*}.0/24"
}

# Initialize nftables chain
init_chain() {
	# Add our chain to the fw4 table (idempotent)
	nft add chain $TABLE $CHAIN 2>/dev/null || true

	# Insert a jump rule from forward chain to our chain if not already present
	if ! nft list chain $TABLE forward 2>/dev/null | grep -q "jump $CHAIN"; then
		nft insert rule $TABLE forward jump $CHAIN
	fi
}

# Flush all rules in our chain
flush_chain() {
	nft flush chain $TABLE $CHAIN 2>/dev/null || true
}

# Remove our chain and the jump rule entirely
remove_chain() {
	local handle
	handle=$(nft -a list chain $TABLE forward 2>/dev/null \
		| grep "jump $CHAIN" \
		| grep -o 'handle [0-9]*' \
		| awk '{print $2}')
	if [ -n "$handle" ]; then
		nft delete rule $TABLE forward handle "$handle" 2>/dev/null || true
	fi
	nft delete chain $TABLE $CHAIN 2>/dev/null || true
}

# Check if a time-based policy is currently active
# Arguments: weekdays start_time end_time
# weekdays: space-separated list of ISO weekday numbers (1=Mon, 7=Sun)
# start_time / end_time: HH:MM format
check_time_active() {
	local weekdays="$1"
	local start_time="$2"
	local end_time="$3"

	local current_day
	current_day=$(date +%u)  # 1=Monday … 7=Sunday

	# Check if today is in the configured weekdays
	local day_match=0
	for d in $weekdays; do
		[ "$d" = "$current_day" ] && day_match=1 && break
	done
	[ "$day_match" = "0" ] && echo "0" && return

	local start_int end_int current_int
	start_int=$(echo "$start_time" | tr -d ':')
	end_int=$(echo "$end_time" | tr -d ':')
	current_int=$(date +%H%M)

	if [ "$start_int" -le "$end_int" ]; then
		# Same-day window (e.g., 08:00 – 18:00)
		if [ "$current_int" -ge "$start_int" ] && [ "$current_int" -lt "$end_int" ]; then
			echo "1"
		else
			echo "0"
		fi
	else
		# Overnight window (e.g., 22:00 – 06:00)
		if [ "$current_int" -ge "$start_int" ] || [ "$current_int" -lt "$end_int" ]; then
			echo "1"
		else
			echo "0"
		fi
	fi
}

# Check if a device (identified by MAC) is currently online via ARP/neighbour table
check_device_online() {
	local mac="$1"
	[ -z "$mac" ] && echo "0" && return
	# ip neigh shows active neighbours; match MAC case-insensitively
	if ip neigh 2>/dev/null | grep -qi "$mac"; then
		echo "1"
	else
		echo "0"
	fi
}

# Send a DingTalk webhook notification
send_dingtalk_alert() {
	local camera_name="$1"
	local camera_ip="$2"

	local webhook_url interval
	webhook_url=$(uci get camera_access_control.settings.dingtalk_webhook_url 2>/dev/null)
	interval=$(uci get camera_access_control.settings.dingtalk_interval 2>/dev/null)
	interval=${interval:-5}

	[ -z "$webhook_url" ] && return

	# Rate-limit alerts: only send once per interval per camera
	local alert_file="${LAST_ALERT_DIR}/$(echo "$camera_ip" | tr '.' '_')"
	local last_alert=0
	[ -f "$alert_file" ] && last_alert=$(cat "$alert_file")

	local now
	now=$(date +%s)
	local elapsed=$(( now - last_alert ))
	local min_secs=$(( interval * 60 ))

	[ "$elapsed" -lt "$min_secs" ] && return

	echo "$now" > "$alert_file"

	local msg
	msg="【摄像头访问控制告警】摄像头 ${camera_name}（${camera_ip}）检测到大流量包发送，疑似正在进行视频传输。请登录路由器确认是否需要阻止。（每 ${interval} 分钟提醒一次）"

	# Escape characters that would break JSON string encoding
	local safe_msg
	safe_msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')

	# Send asynchronously so we don't block
	curl -s -m 10 -X POST "$webhook_url" \
		-H 'Content-Type: application/json' \
		-d "{\"msgtype\":\"text\",\"text\":{\"content\":\"${safe_msg}\"}}" \
		>/dev/null 2>&1 &
}

# Add nftables rules for one camera under an active policy
# Arguments: camera_ip  policy_type  section_name  lan_subnet  camera_name
add_camera_rules() {
	local ip="$1"
	local type="$2"
	local section="$3"
	local lan_subnet="$4"
	local camera_name="$5"

	# LAN whitelist: always allow large packets to stay within the LAN
	nft add rule $TABLE $CHAIN \
		ip saddr "$ip" ip daddr "$lan_subnet" accept

	if [ "$type" = "block" ]; then
		# Drop large UDP packets (video streaming)
		nft add rule $TABLE $CHAIN \
			ip saddr "$ip" ip protocol udp meta length \> 1000 counter drop
		# Drop large TCP packets (video streaming)
		nft add rule $TABLE $CHAIN \
			ip saddr "$ip" ip protocol tcp meta length \> 1000 counter drop

	elif [ "$type" = "limit" ]; then
		local speed
		config_get speed "$section" speed "512"

		# Rate-limit large packets: allow up to <speed> kbytes/s, drop excess.
		# The 'limit rate' statement acts as a shared token-bucket for this rule,
		# effectively capping this specific camera's throughput.
		nft add rule $TABLE $CHAIN \
			ip saddr "$ip" ip protocol udp meta length \> 1000 \
			limit rate "${speed}" kbytes/second counter accept
		nft add rule $TABLE $CHAIN \
			ip saddr "$ip" ip protocol udp meta length \> 1000 counter drop

		nft add rule $TABLE $CHAIN \
			ip saddr "$ip" ip protocol tcp meta length \> 1000 \
			limit rate "${speed}" kbytes/second counter accept
		nft add rule $TABLE $CHAIN \
			ip saddr "$ip" ip protocol tcp meta length \> 1000 counter drop
	fi
}

# Process a single policy section (called by config_foreach)
# Extra args passed via globals because config_foreach only passes the section name
_cam_section=""
_cam_ip=""
_cam_mac=""
_cam_name=""
_lan_subnet=""

process_policy() {
	local section="$1"

	local policy_camera policy_enabled activation_type policy_type
	config_get policy_camera    "$section" camera
	config_get policy_enabled   "$section" enabled "1"
	config_get activation_type  "$section" activation_type "time"
	config_get policy_type      "$section" type "block"

	# Only handle policies belonging to the current camera
	[ "$policy_camera" != "$_cam_section" ] && return
	[ "$policy_enabled" != "1" ] && return

	local active=0

	if [ "$activation_type" = "time" ]; then
		local weekdays start_time end_time
		config_get weekdays   "$section" weekdays   ""
		config_get start_time "$section" start_time ""
		config_get end_time   "$section" end_time   ""
		if [ -n "$weekdays" ] && [ -n "$start_time" ] && [ -n "$end_time" ]; then
			active=$(check_time_active "$weekdays" "$start_time" "$end_time")
		fi

	elif [ "$activation_type" = "device" ]; then
		local trigger_mac
		config_get trigger_mac "$section" trigger_mac ""
		if [ -n "$trigger_mac" ]; then
			active=$(check_device_online "$trigger_mac")
		fi
	fi

	[ "$active" = "1" ] && add_camera_rules \
		"$_cam_ip" "$policy_type" "$section" "$_lan_subnet" "$_cam_name"
}

# Process a single camera section (called by config_foreach)
process_camera() {
	local section="$1"

	local camera_ip camera_name camera_enabled
	config_get camera_ip      "$section" ip      ""
	config_get camera_name    "$section" name    "$section"
	config_get camera_enabled "$section" enabled "1"

	[ "$camera_enabled" != "1" ] && return
	[ -z "$camera_ip" ]          && return

	# Set globals used by process_policy
	_cam_section="$section"
	_cam_ip="$camera_ip"
	_cam_name="$camera_name"
	_lan_subnet="$LAN_SUBNET"

	config_foreach process_policy policy
}

# Apply all camera rules from UCI config
apply_all_rules() {
	LAN_SUBNET=$(get_lan_subnet)
	init_chain
	flush_chain
	config_foreach process_camera camera
}

# ---- Alert monitoring ----
# Read nftables counter for a camera and send alert if packets increased
check_camera_counter() {
	local ip="$1"
	local name="$2"

	# Sum all counter values in our chain that match this camera's saddr
	local total=0
	while IFS= read -r line; do
		local pkt
		pkt=$(echo "$line" | grep -o 'packets [0-9]*' | awk '{print $2}')
		[ -n "$pkt" ] && total=$(( total + pkt ))
	done <<-EOF
		$(nft list chain $TABLE $CHAIN 2>/dev/null | grep "ip saddr $ip" | grep "counter")
	EOF

	local key
	key=$(echo "$ip" | tr '.' '_')
	local counter_file="${COUNTER_DIR}/${key}"

	local prev=0
	[ -f "$counter_file" ] && prev=$(cat "$counter_file")

	echo "$total" > "$counter_file"

	# If counter increased since last check, send an alert
	[ "$total" -gt "$prev" ] && send_dingtalk_alert "$name" "$ip"
}

check_all_alerts() {
	config_foreach _check_camera_alert camera
}

_check_camera_alert() {
	local section="$1"
	local ip name enabled
	config_get ip      "$section" ip      ""
	config_get name    "$section" name    "$section"
	config_get enabled "$section" enabled "1"

	[ "$enabled" != "1" ] && return
	[ -z "$ip" ] && return
	check_camera_counter "$ip" "$name"
}

# ---- Entry point ----
load_config

case "$1" in
	apply)
		apply_all_rules
		;;
	check_alerts)
		check_all_alerts
		;;
	stop)
		remove_chain
		;;
	*)
		echo "Usage: $0 {apply|check_alerts|stop}" >&2
		exit 1
		;;
esac
