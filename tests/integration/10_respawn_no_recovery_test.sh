#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

# Recovery runs once per boot (tmpfs marker); a mid-uptime supervisor respawn
# must RESUME, not re-run recovery. Guards the marker: without it, a respawn
# under an untrusted clock would conservatively roll back an in-window apply just
# because the supervisor restarted. Uses a throwaway package (no service reload),
# so a wrong rollback is harmless to observe.
$SSH 'rm -f /etc/config/actest; touch /etc/config/actest; uci -q set actest.s=actest; uci -q set actest.s.v=A; uci -q commit actest'
$SSH 'rm -f /var/run/apply-confirm.clock-trusted'   # simulate a box with no NTP
$SSH "apply-confirm stage --timeout 120 --package actest" >/dev/null || fail "stage failed"
$SSH 'uci -q set actest.s.v=B; uci -q commit actest'

# Wait for the daemon to stamp a real pid, then kill it (never kill <= 1).
pid=0; i=0
while [ "$i" -lt 12 ]; do
	pid=$($SSH "apply-confirm status" | sed -n 's/^pid=//p')
	{ [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null; } && break
	sleep 1; i=$((i + 1))
done
[ "$pid" -gt 1 ] 2>/dev/null || fail "no supervisor pid recorded (got '$pid')"
$SSH "kill -9 $pid" || true
sleep 9

v=$($SSH "uci -q get actest.s.v" 2>/dev/null || echo MISSING)
[ "$v" = B ] || fail "respawn rolled back an in-window apply (v=$v); per-boot marker not honored"
$SSH "apply-confirm status" | grep -q '^phase=armed' || fail "apply not armed after respawn"
echo "respawn under untrusted clock resumed without rolling back (marker honored)."

# cleanup
$SSH 'apply-confirm rollback >/dev/null 2>&1 || true; rm -f /etc/config/actest; touch /var/run/apply-confirm.clock-trusted'
