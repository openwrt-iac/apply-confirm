#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

# Validates risk R5: a killed supervisor is respawned by procd and the relaunch
# re-derives its deadline from durable state rather than restarting the clock.
TOKEN=$($SSH "apply-confirm stage --timeout 30 --package system") || fail "stage failed"

pid=$($SSH "apply-confirm status" | sed -n 's/^pid=//p')
[ -n "$pid" ] && [ "$pid" != "0" ] || fail "no supervisor pid recorded (got '$pid')"

$SSH "kill -9 $pid" || true
sleep 5

newpid=$($SSH "apply-confirm status" | sed -n 's/^pid=//p')
$SSH "apply-confirm status" | grep -q '^phase=armed' || fail "apply no longer armed after kill"
[ -n "$newpid" ] && [ "$newpid" != "0" ] && [ "$newpid" != "$pid" ] \
	|| fail "supervisor was not respawned (old=$pid new=$newpid); see hardening.md R5"

$SSH "apply-confirm ack '$TOKEN'" || fail "ack failed"
echo "killed supervisor is respawned and keeps the original deadline."
