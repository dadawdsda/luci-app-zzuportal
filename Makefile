# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-zzuportal
PKG_VERSION:=26.7.16
PKG_RELEASE:=1

LUCI_TITLE:=ZZU Portal automatic authentication client
LUCI_DEPENDS:=+luci-base +uhttpd +curl +coreutils-base64 +jq
LUCI_PKGARCH:=all

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Dr.Clef <3010719673@qq.com>


include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
