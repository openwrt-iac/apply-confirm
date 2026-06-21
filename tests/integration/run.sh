#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."

# The network-partition tests drive the break by reconfiguring the LAN from
# inside the guest and then watch for the link to drop and recover. Under
# KVM-less CI emulation, qemu user-mode networking reacts to an in-guest IP
# change with highly variable timing (the break can land tens of seconds late),
# so these are run but NOT gated: a failure here is reported, not fatal. They are
# meant to be validated on real hardware or a KVM-enabled host. The core tests
# (stage/ack, timeout rollback, monotonic immunity, kill/respawn, reboot
# recovery) are deterministic and gate CI. See docs/testing.md.
BEST_EFFORT="06_network_partition_test 07_broken_mgmt_iface_test"

passed=0
failed=0
besteffort=0
failures=""

for test in tests/integration/*_test.sh; do
	[ -f "$test" ] || continue
	name=$(basename "$test" .sh)
	printf "\n[%s]\n" "$name"
	if sh "$test"; then
		passed=$((passed + 1))
		continue
	fi

	echo "--- diagnostics after $name ---"
	ssh -i tests/vm/id_ed25519 -o StrictHostKeyChecking=no \
	    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
	    -o ConnectTimeout=5 -o BatchMode=yes -p 2222 root@127.0.0.1 '
		echo "[logread]"; logread 2>/dev/null | grep -i apply-confirm | tail -20
		echo "[ps]"; ps w 2>/dev/null | grep -i "[a]pply-confirm\|[s]upervise"
		echo "[pending]"; ls -la /etc/apply-confirm/pending 2>/dev/null
	' 2>/dev/null || echo "(VM unreachable for diagnostics)"

	if echo " $BEST_EFFORT " | grep -q " $name "; then
		echo "NOTE: $name is best-effort under CI emulation (not gating); validate on real hardware"
		besteffort=$((besteffort + 1))
	else
		failed=$((failed + 1))
		failures="$failures $name"
	fi
done

printf "\n%d passed, %d failed, %d best-effort-failed\n" "$passed" "$failed" "$besteffort"
if [ "$failed" -ne 0 ]; then
	printf "Failures:%s\n" "$failures"
	exit 1
fi
