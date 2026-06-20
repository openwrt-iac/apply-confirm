# apply-confirm

> Working name. Not yet final. See `design/design-issue.md`.

A commit-confirmed-apply rollback supervisor for OpenWrt. Stage a config change
with a deadline; if it is not acknowledged in time, the pre-change snapshot is
restored and services are reloaded to their prior state. The rollback fires
locally and survives a reboot, a process kill, and the management interface
going down, which is the case it exists for: you push a change over the only
network path you have, the change breaks that path, and nobody is left to undo
it.

OpenWrt already ships a weaker form of this in rpcd (`uci.apply {rollback,
timeout}`). That state lives in an in-memory ubus session, has a 90s floor,
allows one global pending apply, and does not survive a reboot. `apply-confirm`
keeps the same vocabulary (`apply` / `confirm` / `rollback`) but is an
independent supervisor with durable state. See `docs/rpcd-apply-path.md` for the
full comparison.

This is a standalone project, not part of uapi. uapi and LuCI integrate by
invoking the CLI, not by absorbing it.

## Usage

```sh
# Snapshot the named packages and arm a 60-second rollback. Prints a token.
TOKEN=$(apply-confirm stage --timeout 60 --package network --package firewall)

# Apply your change (uapi write, uci set + commit, /etc/init.d/network reload...).

# If the management path is still up, confirm within the window.
apply-confirm ack "$TOKEN"

# Otherwise the deadline fires and the snapshot is restored automatically.
# An operator on the console can also force it early, with no network:
apply-confirm rollback
```

## Status

v0 / pre-release. Shell + procd + a persistent state file. See `docs/` for the
architecture, the CLI contract, and the hardening rationale.

## License

MIT. See `LICENSE`.
