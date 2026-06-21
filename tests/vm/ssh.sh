#!/bin/sh
# ConnectTimeout bounds the connect phase only (not command runtime), so a VM
# that is down or mid-boot fails fast instead of hanging the whole suite.
exec ssh -i "$(dirname "$0")/id_ed25519" \
	-o StrictHostKeyChecking=no \
	-o UserKnownHostsFile=/dev/null \
	-o LogLevel=ERROR \
	-o ConnectTimeout=10 \
	-p 2222 root@127.0.0.1 "$@"
