# Hardening: the broken-management-interface scenario

The case this package exists for. An operator pushes a `network` or `firewall`
change over the only path to the box (SSH, HTTPS), the change reconfigures that
path, the change is wrong, the path drops, **the ack can never arrive**, and a
rollback is exactly what must fix it.

## Why the rollback still fires

1. **The trigger is local and network-independent.** The deadline is a local
   monotonic sleep in a local process plus a local boot hook. Nothing about
   firing the rollback touches the network. The network breaking is the expected
   condition, not a failure mode.
2. **Everything the rollback needs is captured at stage time**, before the
   breaking change: the snapshot and the service list live in durable state.
   `do_rollback` resolves nothing new off the network.
3. **Restore is idempotent and lock-guarded.** The live supervisor, a respawned
   supervisor, and the boot hook can all attempt it; the exclusive lock plus the
   `armed` -> `rolledback` phase flip make all but the first a no-op.
4. **Reload-during-restore failure leaves uci restored.** uci is back to the
   prior, working config regardless of whether the daemon reload returns nonzero;
   the broken change is never reinstated. Classified `rolledback_reload_failed`,
   CLI exit 5.

Ordering for the broken-mgmt case: stage records snapshot + services + deadline
durably -> caller applies the breaking change -> mgmt path dies -> ack cannot
arrive -> the monotonic deadline elapses in the local supervisor (or the boot
hook fires on the reboot the breakage caused) -> exclusive lock -> uci import +
commit per package -> coalesced reload -> mgmt path restored -> phase rolledback.

## Riskiest unknowns (verify in the VM before locking)

**R5 - procd respawn for a process that legitimately exits.** Liveness leans on
respawn-while-armed without respawn-storming after a clean ack. The supervisor
exits 0 once the apply is no longer armed, and a relaunch immediately re-checks
phase and exits, but procd's respawn-regardless-of-exit-code behavior on the
target release must be confirmed. Fallback: a `setsid`-launched supervisor with
procd doing only boot recovery. This is the top thing to validate on real
hardware.

**R3 - supervisor killed, no reboot, within this uptime.** If the supervisor is
killed and the box neither reboots nor respawns it, the timer never fires that
uptime. Mitigated by procd respawn (R5); the boot hook is the ultimate backstop.
The residual gap is documented; an optional cron backstop is a future toggle.

**Clock-trust dependency.** A box with no NTP and no RTC never trusts its clock,
so an armed apply surviving a reboot always takes the conservative rollback
branch. Safe by design, but such a box cannot re-arm across a reboot. Acceptable
for v0.

**R1 - overlay/flash write churn.** Snapshotting to `/etc` writes flash on every
stage. Bounded by the single-pending-apply rule; flag for flash-wear-sensitive
boards.

**R4 - network reload bounces the management link during restore.** Expected and
benign: the restore puts the working config back, so the bounce ends with a
reachable box. We `reload` rather than `restart` to minimize it. The acceptance
test asserts the box returns, so a future change from `reload` to `restart` is
caught.
