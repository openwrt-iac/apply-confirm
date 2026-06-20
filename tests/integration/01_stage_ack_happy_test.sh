#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

orig=$($SSH "uci get system.@system[0].hostname")
TOKEN=$($SSH "apply-confirm stage --timeout 30 --package system") || fail "stage failed"
echo "staged token=$TOKEN"

$SSH "apply-confirm status" | grep -q '^phase=armed' || fail "not armed after stage"

$SSH "uci set system.@system[0].hostname='acked-host'; uci commit system"
$SSH "apply-confirm ack '$TOKEN'" || fail "ack failed"

# status returns 4 once the window has closed; capture it without set -e aborting.
rc=0; $SSH "apply-confirm status" >/dev/null 2>&1 || rc=$?
[ "$rc" = 4 ] || fail "expected status rc 4 after ack, got $rc"

now=$($SSH "uci get system.@system[0].hostname")
[ "$now" = "acked-host" ] || fail "acked change was not kept (got $now)"

$SSH "uci set system.@system[0].hostname='$orig'; uci commit system"
echo "stage -> ack keeps the change."
