#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

# Reboot survival with the default reboot_policy=rollback: the clock-trust flag
# is on tmpfs, so it is absent after a power-cycle, so boot recovery takes the
# conservative rollback branch.
#
# We power-cycle via QEMU stop+start rather than an in-place `reboot`: the disk
# image (and thus the on-disk armed state) persists, it is a genuine cold boot of
# the box, and it is reliable under KVM-less CI emulation where an in-place guest
# reboot can stall. The boot-recovery code path exercised is identical.
orig=$($SSH "uci get system.@system[0].hostname")
$SSH "apply-confirm stage --timeout 120 --package system" >/dev/null || fail "stage failed"
$SSH "uci set system.@system[0].hostname='survived-reboot'; uci commit system; sync"

echo "armed with a long window, applied a change, power-cycling without acking"
tests/vm/stop.sh
tests/vm/start.sh
TIMEOUT=240 tests/vm/wait.sh || fail "VM did not come back after power-cycle"
sleep 8

now=$($SSH "uci get system.@system[0].hostname")
[ "$now" = "$orig" ] || fail "boot recovery did not roll back the unconfirmed change (got $now)"

# No zombie: recovery must REMOVE the record, not leave it armed. Regression
# guard for the boot-time recover/supervisor race that re-created a deleted
# record (snapshot gone, stale deadline) and wedged the single-pending slot.
$SSH "apply-confirm list" | grep -q 'armed$' && fail "zombie armed record after boot recovery" || true

# The single-pending slot must be free afterwards: a fresh stage must succeed
# (exit 0), not be rejected as already_armed (exit 3).
t=$($SSH "apply-confirm stage --timeout 10 --package system") || fail "slot not free after recovery (stage rejected)"
$SSH "apply-confirm ack '$t' >/dev/null 2>&1"

echo "an unconfirmed change is rolled back after a reboot, leaving no zombie."
