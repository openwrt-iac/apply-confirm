# Changelog

All notable changes to this project are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). As a safety
primitive it ships RC-first; even minor releases soak as `-rc` before final.

## [Unreleased]

### Changed
- The default `--service` reload set is now a built-in deterministic map rather
  than a same-name guess: `dhcp`->dnsmasq+odhcpd, `wireless`->network,
  `system`->system+log+sysntpd, else a same-named init script if one exists. It
  never reads ucitrack, so reload behavior is identical with or without LuCI
  installed. `system` now also reloads `log` and `sysntpd` (logging and the ntp
  timeserver), which `/etc/init.d/system` alone does not. Callers passing
  `--service` (uapi) are unaffected. Re #5.
- Documented the one-global-pending-window concurrency model explicitly.

## [0.1.0-rc1]

Initial pre-release. A commit-confirmed-apply rollback supervisor: stage a uci
change with a deadline, restore the pre-change snapshot if it is not acked in
time. Shell + procd + a durable state file on the rw overlay.

### Added
- CLI (`stage` / `ack` / `rollback` / `status` / `list`) with a documented
  exit-code contract (`docs/cli-contract.md`).
- Durable, reboot-surviving state with a dual monotonic/absolute deadline and a
  boot-recovery decision table that fails safe on an untrusted clock.
- procd service for liveness and an NTP hotplug clock-trust hook.
- OpenWrt package (`PKGARCH:=all`, `DEPENDS:=+procd`).
- Unit suite and a QEMU integration suite gated on `07_broken_mgmt_iface`.

### Known gaps
- Risk R5 (procd respawn-while-armed) needs validation on real hardware.
- The name is a working placeholder pending design issue #1.
