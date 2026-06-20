# Packaging and release

## Package

`build/openwrt/apply-confirm/Makefile` is a standard OpenWrt package. Pure shell,
so `PKGARCH:=all` (arch-neutral, like uapi). `DEPENDS:=+procd`; everything else
(`uci`, `ubus`, `logger`, `flock`) is on every OpenWrt. `/etc/config/apply-
confirm` is a conffile so operator settings survive upgrade.

Installed layout:

| Path | Role |
|------|------|
| `/usr/sbin/apply-confirm` | CLI dispatcher |
| `/usr/lib/apply-confirm/*.sh` | sourced libraries |
| `/etc/init.d/apply-confirm` | procd service: boot recovery + supervise |
| `/etc/config/apply-confirm` | conffile |
| `/etc/hotplug.d/ntp/20-apply-confirm` | mark clock trusted on NTP sync |
| `/etc/uci-defaults/99-apply-confirm` | create the state dir on install |

## Build

```sh
make stage                       # populate build/openwrt/apply-confirm/files/
# then, inside an OpenWrt SDK:
ln -s .../apply-confirm/build/openwrt/apply-confirm package/apply-confirm
make defconfig
make package/apply-confirm/compile V=s
```

Output: `bin/packages/all/.../apply-confirm-<version>.apk`.

## Release discipline (heavier than uapi)

This is a safety primitive, so soak is heavier and there is no ship-as-patch:

- **RC first, always.** Even minor releases tag `-rc` and soak before final.
- **The acceptance gate is `07_broken_mgmt_iface`.** It must pass on real
  hardware, not only in QEMU, before a final tag.
- **Signed annotated tags**, branch + PR only, never a direct push to `main`.
- Verify R5 (procd respawn behavior) on the target release as part of RC soak.
