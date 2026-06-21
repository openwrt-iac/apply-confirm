SSH="tests/vm/ssh.sh"

# Fast-failing reachability probe for the partition tests: a plain ssh during a
# deliberate blackhole would hang on the full TCP connect timeout, so bound it.
vm_reachable() {
	ssh -i tests/vm/id_ed25519 \
	    -o StrictHostKeyChecking=no \
	    -o UserKnownHostsFile=/dev/null \
	    -o LogLevel=ERROR \
	    -o ConnectTimeout=3 \
	    -o BatchMode=yes \
	    -p 2222 root@127.0.0.1 true 2>/dev/null
}

# Push the staged package tree onto the VM and enable the service. Guarded by a
# tmpfs sentinel so a second call is a no-op.
install_apply_confirm() {
	$SSH 'test -f /var/run/apply-confirm-installed' 2>/dev/null && return 0
	make stage >/dev/null
	tar c -C build/openwrt/apply-confirm/files . | $SSH '
		tar x -C / &&
		chmod +x /usr/sbin/apply-confirm /etc/init.d/apply-confirm /etc/uci-defaults/99-apply-confirm &&
		sh /etc/uci-defaults/99-apply-confirm &&
		/etc/init.d/apply-confirm enable
	'
	# Tests assert against a clean pending dir.
	$SSH 'rm -rf /etc/apply-confirm/pending && mkdir -p /etc/apply-confirm/pending'
	$SSH 'touch /var/run/apply-confirm-installed'
}

# Reset state between tests without re-pushing the package.
reset_apply_confirm() {
	$SSH '
		rm -rf /etc/apply-confirm/pending && mkdir -p /etc/apply-confirm/pending
		rm -f /tmp/ac-reload-fail-once
		/etc/init.d/apply-confirm stop 2>/dev/null || true
	'
}
