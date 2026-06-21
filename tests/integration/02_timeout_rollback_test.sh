#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

orig=$($SSH "uci get system.@system[0].hostname")
$SSH "apply-confirm stage --timeout 3 --package system" >/dev/null || fail "stage failed"

$SSH "uci set system.@system[0].hostname='unconfirmed'; uci commit system"
echo "armed with a 3s window, applied a change, not acking"

sleep 8

now=$($SSH "uci get system.@system[0].hostname")
[ "$now" = "$orig" ] || fail "unconfirmed change was not rolled back (got $now)"

# status returns 4 once the record is gone; capture it without set -e aborting.
rc=0; $SSH "apply-confirm status" >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "expected no pending record after rollback, got rc $rc"

echo "unconfirmed apply rolled back on the deadline."
