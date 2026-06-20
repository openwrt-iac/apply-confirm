# Architecture

One invariant the whole design serves: **an armed apply that is not acked gets
its pre-apply snapshot restored, across a reboot, a supervisor kill, or a broken
management interface.**

Two actors. The **arming caller** (uapi / LuCI / shell) snapshots, applies its
change, then acks or does not. The **supervisor** owns only a timer and a
snapshot; its single job is to restore on deadline if not acked. The supervisor
never depends on the management network, on rpcd's session, or on its own
process staying alive.

## State

Durable, on the rw overlay so it survives a reboot (`/tmp` and `/var` are tmpfs).

- Control state: `/etc/apply-confirm/pending/<token>.state`, line-oriented
  `key=value` so the boot hook parses it with nothing but the shell.
- Snapshot payload: `<token>.d/<pkg>.export`, one `uci export` per package,
  co-located on the overlay so it survives the reboot too.

Fields: `token phase deadline deadline_mono packages services snapshot_dir pid
created reason`. `phase`: `armed` -> `committed` | `rolledback` |
`rolledback_reload_failed`.

**Atomic writes.** Every mutation writes a sibling temp and renames over the
target; rename within a filesystem is atomic, so a reader never sees a torn file
and a power cut leaves either the old file or the complete new one. At stage time
the snapshot files are written first and the `.state` file last: its landing is
the commit point. A crash before it means nothing is armed, and the caller was
not yet told it was armed.

**One pending apply at a time**, like rpcd, enforced by an exclusive flock on
`/var/lock/apply-confirm.lock`. Overlapping rollbacks across different package
sets are not worth the complexity on a 32MB box, and the safety story is far
easier to reason about with one outstanding snapshot.

## Durable timer

A dual deadline defeats the no-RTC clock-jump problem (a router with no RTC boots
at a stale time, then sysntpd jumps the wall clock forward by years).

- **While the box stays up:** the live supervisor sleeps against the **monotonic**
  clock (`/proc/uptime`) in bounded chunks (default 5s), re-checking phase each
  wake so an ack exits it within one chunk. An NTP jump cannot fire it early or
  late. It re-reads `deadline_mono` each wake so a boot-time re-arm is honored.
- **Across a reboot:** monotonic resets, so the boot hook uses the **absolute**
  deadline, but only once the clock is trusted. Trust is signalled by sysntpd's
  `/etc/hotplug.d/ntp` `stratum` event, which sets `/var/run/apply-confirm.
  clock-trusted` (tmpfs, so absent again on the next boot).

procd runs the supervisor for liveness (`respawn`): a killed supervisor comes
back and re-derives its deadline from durable state; it exits cleanly once the
apply is no longer armed. See `docs/hardening.md` risk R5.

## Boot recovery decision table

Run early from the init `boot()` and again from the NTP hotplug hook.

| Phase at boot | Clock | Condition | Action |
|---------------|-------|-----------|--------|
| committed / rolledback | any | leftover cleanup | remove record |
| rolledback_reload_failed | any | forensics | retain, no-op |
| armed | trusted | now >= deadline | roll back now |
| armed | trusted | now < deadline | re-arm for the remainder |
| armed | untrusted | `reboot_policy=rollback` (default) | roll back now |
| armed | untrusted | `reboot_policy=rearm-on-trusted-clock` | defer to NTP hook |

The untrusted-clock default is the safety crux: a box that rebooted mid-window
was never acked and the operator was not present, and the reboot was more likely
caused by the change than coincident with it. Rolling back is the failing-safe
direction.

## Snapshot and restore

Mirrors uapi's transaction recipe, in shell:

- snapshot: `uci -q export <pkg>` to a temp file, rename.
- restore: per package `uci -q import <pkg>` then `uci -q commit <pkg>`, then one
  coalesced `reload` (not `restart`, to minimize the management-link bounce) of
  the recorded services.
- If the reload fails during restore, uci is already back to the prior config, so
  it is left restored and the broken change is never reinstated; the phase becomes
  `rolledback_reload_failed` (CLI exit 5) and the record is retained.

Rollback is idempotent: the lock plus the phase flip make a racing second caller
(a respawned supervisor and the boot hook, say) a no-op.
