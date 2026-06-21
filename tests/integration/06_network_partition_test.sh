#!/bin/sh
set -eu
. tests/integration/lib/install_apply_confirm.sh
install_apply_confirm
reset_apply_confirm
fail() { echo "FAIL: $*"; exit 1; }

# The local trigger fires even when the ack channel is gone. We arm and then
# break the very interface the host reaches the VM on, from a detached script so
# the breaking command does not need the connection to survive. The only way the
# host regains SSH is the local rollback restoring the working config.
proto=$($SSH "uci get network.lan.proto")
[ "$proto" = "dhcp" ] || fail "expected lan on dhcp in the VM harness (got $proto)"

$SSH "cat > /tmp/partition.sh" <<'EOS'
#!/bin/sh
apply-confirm stage --timeout 15 --package network >/tmp/ac.token 2>/dev/null
uci set network.lan.proto='static'
uci set network.lan.ipaddr='10.99.99.99'
uci set network.lan.netmask='255.255.255.0'
uci commit network
/etc/init.d/network reload
EOS
$SSH "nohup sh /tmp/partition.sh >/tmp/partition.log 2>&1 &" || true
echo "armed and blackholed the management interface; ack can no longer arrive"

# The break lands a few seconds in (stage snapshots and starts the supervisor
# first), so poll for the drop rather than assuming a fixed delay.
dropped=0; i=0
while [ "$i" -lt 25 ]; do
	vm_reachable || { dropped=1; break; }
	sleep 1; i=$((i + 1))
done
[ "$dropped" = 1 ] || fail "management interface never dropped; test is not exercising the scenario"

ok=0; i=0
while [ "$i" -lt 60 ]; do
	vm_reachable && { ok=1; break; }
	sleep 1; i=$((i + 1))
done
[ "$ok" = 1 ] || fail "management interface never recovered (local rollback did not fire)"

$SSH "uci get network.lan.proto" | grep -q dhcp || fail "lan proto not restored to dhcp"
echo "local rollback restored the management interface after a partition."
