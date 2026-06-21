#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

TOKEN=$($SSH "apply-confirm stage --timeout 30 --package system") || fail "stage failed"

# Jump the wall clock years into the future. busybox date has no relative
# parsing, so use the legacy MMDDhhmmYYYY set form. The live countdown is
# monotonic, so this must NOT fire the rollback early.
$SSH "date 010100002035 >/dev/null 2>&1" || fail "could not set the clock"
sleep 5

$SSH "apply-confirm status" | grep -q '^phase=armed' \
	|| fail "a wall-clock jump fired the rollback early (countdown is not monotonic)"

$SSH "apply-confirm ack '$TOKEN'" || fail "ack failed"
# Resync the clock for the following tests (best effort; NTP corrects it).
$SSH "/etc/init.d/sysntpd restart >/dev/null 2>&1" || true

echo "monotonic countdown is immune to wall-clock jumps."
