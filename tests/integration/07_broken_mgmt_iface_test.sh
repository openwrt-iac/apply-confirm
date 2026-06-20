#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

# THE ACCEPTANCE TEST. The full scenario the package exists for: a change pushed
# over the only path to the box breaks that path, the operator cannot ack, and
# the box must recover itself at the deadline. A change that cannot keep this
# green does not merge (see CLAUDE.md).
#
# Stronger than 06: we assert recovery happens AROUND the deadline, not merely
# eventually, so a too-long or absent timer is caught.

proto=$($SSH "uci get network.lan.proto")
[ "$proto" = "dhcp" ] || fail "expected lan on dhcp in the VM harness (got $proto)"

WINDOW=15
$SSH "cat > /tmp/breakit.sh" <<EOS
#!/bin/sh
apply-confirm stage --timeout $WINDOW --package network >/tmp/ac.token 2>/dev/null
uci set network.lan.proto='static'
uci set network.lan.ipaddr='10.99.99.99'
uci set network.lan.netmask='255.255.255.0'
uci commit network
/etc/init.d/network reload
EOS

start=$(date +%s)
$SSH "nohup sh /tmp/breakit.sh >/tmp/breakit.log 2>&1 &" || true
echo "blackholed the management interface at t=0, deadline at t=${WINDOW}s"

# Confirm the link actually dropped before trusting the recovery signal.
sleep 4
if vm_reachable; then fail "management interface did not drop; test is not exercising the scenario"; fi

ok=0
i=0
while [ "$i" -lt 40 ]; do
	if vm_reachable; then ok=1; break; fi
	sleep 1
	i=$((i + 1))
done
[ "$ok" = 1 ] || fail "box never became reachable again (rollback did not fire)"

recovered=$(( $(date +%s) - start ))
echo "reachable again after ${recovered}s (deadline was ${WINDOW}s)"
[ "$recovered" -ge "$WINDOW" ] || fail "recovered before the deadline ($recovered < $WINDOW); rollback fired too early"
[ "$recovered" -le $(( WINDOW + 25 )) ] || fail "recovery took too long ($recovered s); timer or reload is slow"

$SSH "uci get network.lan.proto" | grep -q dhcp || fail "lan proto not restored to dhcp"
echo "ACCEPTANCE: the box recovered itself at the deadline after locking out its operator."
