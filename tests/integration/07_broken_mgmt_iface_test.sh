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
# Stronger than 06: we assert the link actually dropped and that recovery does
# not happen before the deadline, so a too-eager or absent timer is caught.

proto=$($SSH "uci get network.lan.proto")
[ "$proto" = "dhcp" ] || fail "expected lan on dhcp in the VM harness (got $proto)"

WINDOW=20
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
echo "blackholed the management interface, deadline at t=${WINDOW}s"

# Poll for the drop (the break lands a few seconds in, after stage runs).
dropped=0; i=0
while [ "$i" -lt 25 ]; do
	vm_reachable || { dropped=1; break; }
	sleep 1; i=$((i + 1))
done
[ "$dropped" = 1 ] || fail "management interface never dropped; test is not exercising the scenario"

ok=0; i=0
while [ "$i" -lt 90 ]; do
	vm_reachable && { ok=1; break; }
	sleep 1; i=$((i + 1))
done
[ "$ok" = 1 ] || fail "box never became reachable again (rollback did not fire)"

recovered=$(( $(date +%s) - start ))
echo "reachable again after ${recovered}s (deadline was ${WINDOW}s)"
[ "$recovered" -ge "$WINDOW" ] || fail "recovered before the deadline ($recovered < $WINDOW); rollback fired too early"

$SSH "uci get network.lan.proto" | grep -q dhcp || fail "lan proto not restored to dhcp"
echo "ACCEPTANCE: the box recovered itself at the deadline after locking out its operator."
