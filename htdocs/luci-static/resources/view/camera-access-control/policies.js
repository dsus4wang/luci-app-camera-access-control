'use strict';
'require view';
'require form';
'require uci';

return view.extend({
	load: function() {
		return uci.load('camera_access_control');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('camera_access_control',
			_('Camera Access Control – Policies'),
			_('Define control policies for each camera. ' +
			  'A policy becomes active when its activation condition is met. ' +
			  'Traffic to the local LAN subnet is always whitelisted.'));

		s = m.section(form.TypedSection, 'policy', _('Policies'));
		s.addremove = true;
		s.anonymous = true;

		/* ---- Basic info ---- */
		o = s.option(form.Value, 'name', _('Policy Name'));
		o.rmempty = false;
		o.placeholder = _('e.g. Block at night');

		/* Camera selection */
		o = s.option(form.ListValue, 'camera', _('Camera'),
			_('The camera this policy applies to'));
		o.rmempty = false;
		uci.sections('camera_access_control', 'camera').forEach(function(cam) {
			var label = (cam.name || cam['.name']) +
				(cam.ip ? ' (' + cam.ip + ')' : '');
			o.value(cam['.name'], label);
		});

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.rmempty = false;

		/* ---- Control type ---- */
		o = s.option(form.ListValue, 'type', _('Control Type'),
			_('How to restrict video transmission from this camera'));
		o.value('block', _('Block (drop packets > 1000 bytes)'));
		o.value('limit', _('Rate Limit (kbytes/s)'));
		o.default = 'block';

		o = s.option(form.Value, 'speed', _('Speed Limit (kbytes/s)'),
			_('Maximum allowed throughput for large packets. ' +
			  'Applied only when Control Type is "Rate Limit".'));
		o.depends('type', 'limit');
		o.datatype = 'uinteger';
		o.placeholder = '512';
		o.default = '512';

		/* ---- Activation condition ---- */
		o = s.option(form.ListValue, 'activation_type', _('Activation Condition'),
			_('When this policy becomes active'));
		o.value('time',   _('Specific time window (weekly schedule)'));
		o.value('device', _('When a specific device comes online'));
		o.default = 'time';

		/* -- Time-based -- */
		o = s.option(form.MultiValue, 'weekdays', _('Active on Days'),
			_('Days of the week when the policy is active'));
		o.depends('activation_type', 'time');
		o.value('1', _('Monday'));
		o.value('2', _('Tuesday'));
		o.value('3', _('Wednesday'));
		o.value('4', _('Thursday'));
		o.value('5', _('Friday'));
		o.value('6', _('Saturday'));
		o.value('7', _('Sunday'));

		o = s.option(form.Value, 'start_time', _('Start Time (HH:MM)'),
			_('Time when the policy becomes active (24-hour format)'));
		o.depends('activation_type', 'time');
		o.placeholder = '22:00';
		o.validate = function(section_id, value) {
			if (!/^\d{2}:\d{2}$/.test(value)) return _('Expected HH:MM format');
			var parts = value.split(':');
			if (parseInt(parts[0]) > 23 || parseInt(parts[1]) > 59)
				return _('Invalid time value');
			return true;
		};

		o = s.option(form.Value, 'end_time', _('End Time (HH:MM)'),
			_('Time when the policy becomes inactive (24-hour format). ' +
			  'Overnight ranges are supported (e.g. 22:00 – 06:00).'));
		o.depends('activation_type', 'time');
		o.placeholder = '06:00';
		o.validate = function(section_id, value) {
			if (!/^\d{2}:\d{2}$/.test(value)) return _('Expected HH:MM format');
			var parts = value.split(':');
			if (parseInt(parts[0]) > 23 || parseInt(parts[1]) > 59)
				return _('Invalid time value');
			return true;
		};

		/* -- Device-based -- */
		o = s.option(form.Value, 'trigger_mac', _('Trigger Device MAC'),
			_('The policy activates when this MAC address is detected on the network ' +
			  '(ARP neighbour table). Example: AA:BB:CC:DD:EE:FF'));
		o.depends('activation_type', 'device');
		o.datatype = 'macaddr';
		o.placeholder = 'AA:BB:CC:DD:EE:FF';

		return m.render();
	}
});
