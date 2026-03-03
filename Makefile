include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-camera-access-control
PKG_VERSION:=1.1
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=dsus4wang

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-camera-access-control
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI support for Camera Access Control
  DEPENDS:=+luci-base +nftables +curl
  PKGARCH:=all
endef

define Package/luci-app-camera-access-control/description
  LuCI application for controlling LAN cameras and their video transmission.
  Uses nftables to block or rate-limit video traffic from specified cameras.
  Supports time-based and device-presence-based activation policies.
  Sends DingTalk webhook alerts when large-packet activity is detected.
endef

define Build/Compile
endef

define Package/luci-app-camera-access-control/install
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-camera-access-control.json \
		$(1)/usr/share/luci/menu.d/

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-camera-access-control.json \
		$(1)/usr/share/rpcd/acl.d/

	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/luci.camera_access_control \
		$(1)/usr/libexec/rpcd/

	$(INSTALL_DIR) $(1)/usr/share/camera-access-control
	$(INSTALL_BIN) ./root/usr/share/camera-access-control/camera-access-control.sh \
		$(1)/usr/share/camera-access-control/

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/camera_access_control \
		$(1)/etc/config/

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/camera-access-control \
		$(1)/etc/init.d/

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/camera-access-control
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/camera-access-control/*.js \
		$(1)/www/luci-static/resources/view/camera-access-control/
endef

$(eval $(call BuildPackage,luci-app-camera-access-control))
