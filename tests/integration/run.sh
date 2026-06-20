#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."

passed=0
failed=0
failures=""

for test in tests/integration/*_test.sh; do
	[ -f "$test" ] || continue
	name=$(basename "$test" .sh)
	printf "\n[%s]\n" "$name"
	if sh "$test"; then
		passed=$((passed + 1))
	else
		failed=$((failed + 1))
		failures="$failures $name"
		echo "--- diagnostics after $name ---"
		ssh -i tests/vm/id_ed25519 -o StrictHostKeyChecking=no \
		    -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
		    -o ConnectTimeout=5 -o BatchMode=yes -p 2222 root@127.0.0.1 '
			echo "[logread]"; logread 2>/dev/null | grep -i apply-confirm | tail -20
			echo "[ps]"; ps w 2>/dev/null | grep -i "[a]pply-confirm\|[s]upervise"
			echo "[pending]"; ls -la /etc/apply-confirm/pending 2>/dev/null
			echo "[service]"; ubus call service list 2>/dev/null | grep -i apply-confirm
		' 2>/dev/null || echo "(VM unreachable for diagnostics)"
	fi
done

printf "\n%d passed, %d failed\n" "$passed" "$failed"
if [ "$failed" -ne 0 ]; then
	printf "Failures:%s\n" "$failures"
	exit 1
fi
