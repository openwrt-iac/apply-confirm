# rpcd's uci apply path, and what we do differently

OpenWrt already ships a commit-confirmed primitive in rpcd. Before building our
own we read its apply path. This is the writeup, and the case for an independent
supervisor rather than extending or wrapping rpcd.

## What rpcd does

rpcd exposes `uci.apply`, `uci.confirm`, and `uci.rollback` over ubus (built into
the rpcd binary, gated by the `luci-base` ACL that lists `apply`/`confirm` among
the allowed `uci` calls).

- `uci.apply { timeout, rollback: true }` commits the staged changes and, when
  `rollback` is set, schedules an automatic revert if no confirm arrives within
  `timeout`.
- `uci.confirm` cancels the pending revert and keeps the change.
- `uci.rollback` reverts immediately.

LuCI drives this from `luci-base`'s ucode controller
(`controller/admin/uci.uc`): `POST /admin/uci/apply_rollback` returns a random
16-char token, the browser polls `POST /admin/uci/confirm` until the deadline,
and the rollback state is stashed in a ubus **session** value:

```
session set rollback = { token, session, timeout: time() + timeout }
```

The default and enforced-minimum timeout is **90 seconds**.

## Its four limits, for our use case

1. **In-memory session state.** The pending rollback lives in a ubus session
   value, not on disk.
2. **No reboot survival.** If the box reboots before confirm, the rollback timer
   is gone and the change stays applied. For the lockout case (a bad change
   reboots or wedges the box) this is exactly the wrong direction.
3. **Single global pending apply.** One outstanding rollback at a time, system
   wide.
4. **Client must poll to confirm**, and the wall-clock `time() + timeout`
   deadline is vulnerable to a clock jump.

## Decision: independent supervisor, not extend or wrap

- **Extend rpcd** (add persistence to its C apply path) is upstream-coupled and
  slow to iterate, and a v0 needs to move.
- **Thin wrapper** over `uci.apply/confirm/rollback` inherits limit 2 (no reboot
  survival), which is the most important gap to close.
- **Independent supervisor** (chosen): our own snapshot + durable state + timer.
  We reuse rpcd's *vocabulary* (`apply` / `confirm` / `rollback`) and uapi's
  *transaction recipe* (export-snapshot, import+commit-restore, reload), but own
  the state so it survives a reboot, a process kill, and a broken mgmt path.

What we add over rpcd, point for point: durable on-disk state (1), boot-time
recovery so an unconfirmed change is rolled back after a reboot (2), and a
monotonic live countdown immune to clock jumps (4). We keep the single-pending
model (3) deliberately; it is the right simplicity for a 32MB box.

Coexistence: we operate at the snapshot/reload layer like LuCI's flow does, and
do not call rpcd's apply. An operator should use one mechanism or the other for a
given change, not both at once.
