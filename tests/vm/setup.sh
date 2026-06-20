#!/bin/sh
set -eu
cd "$(dirname "$0")"

IMAGE_URL=https://downloads.openwrt.org/releases/25.12.4/targets/x86/64/openwrt-25.12.4-x86-64-generic-ext4-combined.img.gz
IMAGE_GZ=openwrt-25.12.4.img.gz
IMAGE=openwrt.img
KEY=id_ed25519

if [ ! -f "$IMAGE_GZ" ]; then
	echo "Downloading $IMAGE_URL"
	curl -fsSL --retry 3 -o "$IMAGE_GZ.tmp" "$IMAGE_URL"
	mv "$IMAGE_GZ.tmp" "$IMAGE_GZ"
fi
if [ ! -f "$IMAGE" ]; then
	gunzip -k -c "$IMAGE_GZ" > "$IMAGE.tmp"
	mv "$IMAGE.tmp" "$IMAGE"
fi
if [ ! -f "$KEY" ]; then
	ssh-keygen -t ed25519 -N '' -f "$KEY" -C apply-confirm-ci -q
fi

if [ -f .injected ] && [ .injected -nt "$KEY.pub" ]; then
	echo "SSH key already injected"
	exit 0
fi

echo "Injecting SSH key into image (requires sudo for loop mount)"
LOOPDEV=$(sudo losetup --find --show --partscan "$PWD/$IMAGE")
MNT=$(mktemp -d)
cleanup() { sudo umount "$MNT" 2>/dev/null || true; sudo losetup -d "$LOOPDEV" 2>/dev/null || true; rmdir "$MNT" 2>/dev/null || true; }
trap cleanup EXIT
sudo mount "${LOOPDEV}p2" "$MNT"

sudo mkdir -p "$MNT/etc/dropbear"
sudo cp "$KEY.pub" "$MNT/etc/dropbear/authorized_keys"
sudo chmod 600 "$MNT/etc/dropbear/authorized_keys"
sudo chown 0:0 "$MNT/etc/dropbear/authorized_keys"

# QEMU user-mode networking hands out 10.0.2.x via DHCP; switch LAN off the
# stock static 192.168.1.1 so the forwarded SSH works on first boot.
sudo mkdir -p "$MNT/etc/uci-defaults"
sudo tee "$MNT/etc/uci-defaults/99-ac-vm-network" >/dev/null <<'UCID'
#!/bin/sh
uci set network.lan.proto='dhcp'
uci delete network.lan.ipaddr 2>/dev/null || true
uci delete network.lan.netmask 2>/dev/null || true
uci commit network
exit 0
UCID
sudo chmod 755 "$MNT/etc/uci-defaults/99-ac-vm-network"
sudo chown 0:0 "$MNT/etc/uci-defaults/99-ac-vm-network"

# A controllable stub service so the reload-failure path is deterministic:
# its reload returns nonzero once when /tmp/ac-reload-fail-once is present.
sudo tee "$MNT/etc/init.d/actest" >/dev/null <<'ACINIT'
#!/bin/sh /etc/rc.common
START=50
USE_PROCD=1
start_service() { :; }
reload_service() {
	if [ -f /tmp/ac-reload-fail-once ]; then
		rm -f /tmp/ac-reload-fail-once
		echo "actest: simulated reload failure" >&2
		return 1
	fi
	return 0
}
ACINIT
sudo chmod 755 "$MNT/etc/init.d/actest"
sudo chown 0:0 "$MNT/etc/init.d/actest"

touch .injected
echo "Image ready"
