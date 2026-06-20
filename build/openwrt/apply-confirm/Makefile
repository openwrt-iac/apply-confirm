include $(TOPDIR)/rules.mk

PKG_NAME:=apply-confirm
PKG_VERSION:=$(shell sed 's/-/_/g' $(CURDIR)/files/VERSION)
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=Guy Godfroy <guy.godfroy@gugod.fr>

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

define Package/apply-confirm
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Commit-confirmed-apply rollback supervisor for OpenWrt
  URL:=https://github.com/openwrt-iac/apply-confirm
  DEPENDS:=+procd
  PKGARCH:=all
endef

define Package/apply-confirm/description
  Stage a uci config change with a deadline; if it is not acknowledged in time,
  restore the pre-change snapshot and reload services to the prior state. The
  rollback fires locally and survives a reboot, a process kill, and a broken
  management interface.
endef

define Package/apply-confirm/conffiles
/etc/config/apply-confirm
endef

# Pure shell, nothing to compile.
define Build/Compile
endef

define Package/apply-confirm/install
	$(CP) ./files/. $(1)/
endef

$(eval $(call BuildPackage,apply-confirm))
