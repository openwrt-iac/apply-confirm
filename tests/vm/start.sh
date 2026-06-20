#!/bin/sh
set -eu
cd "$(dirname "$0")"

IMAGE=openwrt.img
PIDFILE=qemu.pid
LOGFILE=qemu.log

[ -f "$IMAGE" ] || { echo "Image not present. Run setup.sh first." >&2; exit 1; }

if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
	echo "VM already running with pid $(cat "$PIDFILE")"
	exit 0
fi

KVM=""
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
	KVM="-enable-kvm -cpu host"
fi

# No -no-reboot: the reboot-midwindow test needs the guest to actually reboot
# and come back, which -no-reboot would turn into a QEMU exit.
# $KVM is deliberately unquoted: it expands to two args or none.
# shellcheck disable=SC2086
qemu-system-x86_64 \
	-display none \
	-m 128 $KVM \
	-drive file="$IMAGE",format=raw,if=virtio \
	-netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22 \
	-device virtio-net,netdev=net0 \
	-serial file:"$LOGFILE" \
	-monitor none \
	-pidfile "$PIDFILE" \
	-daemonize

echo "VM booted, pid $(cat "$PIDFILE"), serial log at $LOGFILE"
