#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

# The --service fallback is a deterministic static map that never reads ucitrack,
# so it produces the same result whether or not LuCI is installed. Exercised
# against the real CLI + state path (no uci/ucitrack manipulation).
derived() {
	# $1 package -> echo the recorded `services`, then ack so nothing rolls back
	_tok=$($SSH "apply-confirm stage --timeout 60 --package $1") || fail "stage $1 failed"
	_svc=$($SSH "apply-confirm status" | sed -n 's/^services=//p')
	$SSH "apply-confirm ack '$_tok'" || fail "ack $1 failed"
	printf '%s' "$_svc"
}

# system gets its full reload set. The map may list a service that is not
# installed (ac_reload_services skips it), so assert the exact mapped string
# rather than init-backing for this special-cased entry.
sys=$(derived system)
echo "system -> [$sys]"
[ "$sys" = "system log sysntpd" ] || fail "expected 'system log sysntpd', got '$sys'"

# Default branch: a same-named package present on the box maps to itself.
fw=$(derived firewall)
echo "firewall -> [$fw]"
[ "$fw" = "firewall" ] || fail "expected 'firewall', got '$fw'"
$SSH "test -x /etc/init.d/firewall" || fail "firewall init script missing on VM"

echo "service map is deterministic and LuCI-independent."
