#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

# Validates risk R5: a killed supervisor is respawned by procd and resumes from
# durable state. The daemon stamps its pid asynchronously (status shows pid=0
# until its next poll), so the test waits for a real pid rather than reading it
# eagerly, and never kills a value <= 1.
TOKEN=$($SSH "apply-confirm stage --timeout 60 --package system") || fail "stage failed"

pid=0; i=0
while [ "$i" -lt 12 ]; do
	pid=$($SSH "apply-confirm status" | sed -n 's/^pid=//p')
	{ [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; } && break
	sleep 1; i=$((i + 1))
done
[ "$pid" -gt 1 ] 2>/dev/null || fail "no supervisor pid recorded (got '$pid')"

$SSH "kill -9 $pid" || true

# procd respawn timeout is ~5s; the relaunched daemon re-stamps its pid on its
# next poll. Wait for a new, different pid.
newpid="$pid"; i=0
while [ "$i" -lt 20 ]; do
	newpid=$($SSH "apply-confirm status" | sed -n 's/^pid=//p')
	{ [ -n "$newpid" ] && [ "$newpid" -gt 1 ] 2>/dev/null && [ "$newpid" != "$pid" ]; } && break
	sleep 1; i=$((i + 1))
done
$SSH "apply-confirm status" | grep -q '^phase=armed' || fail "apply no longer armed after kill"
{ [ "$newpid" -gt 1 ] 2>/dev/null && [ "$newpid" != "$pid" ]; } \
	|| fail "supervisor was not respawned (old=$pid new=$newpid); see hardening.md R5"

$SSH "apply-confirm ack '$TOKEN'" || fail "ack failed"
echo "killed supervisor respawned and resumed from durable state ($pid -> $newpid)."
