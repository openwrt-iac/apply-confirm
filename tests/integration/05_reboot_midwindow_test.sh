#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

# Reboot survival with the default reboot_policy=rollback: the clock-trust flag
# is on tmpfs, so it is absent at boot, so boot recovery takes the conservative
# rollback branch before sysntpd resyncs.
orig=$($SSH "uci get system.@system[0].hostname")
$SSH "apply-confirm stage --timeout 120 --package system" >/dev/null || fail "stage failed"
$SSH "uci set system.@system[0].hostname='survived-reboot'; uci commit system"

echo "armed with a long window, applied a change, rebooting without acking"
$SSH "sync; reboot" || true
sleep 8
TIMEOUT=120 tests/vm/wait.sh || fail "VM did not come back after reboot"
sleep 8

now=$($SSH "uci get system.@system[0].hostname")
[ "$now" = "$orig" ] || fail "boot recovery did not roll back the unconfirmed change (got $now)"

echo "an unconfirmed change is rolled back after a reboot."
