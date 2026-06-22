# Snapshot, restore, reload, and the rollback itself. Mirrors uapi's transaction
# recipe (uci export to snapshot, uci import + commit to restore, init.d reload),
# lifted out of a synchronous HTTP request and onto a durable deadline.

ac_init_exists() { [ -x "/etc/init.d/$1" ]; }

# Deterministic package->service reload map, used when the caller gives no
# explicit --service. Never reads ucitrack, so behavior is identical whether or
# not LuCI is installed. Only packages whose reload set differs from a same-named
# init script are special-cased; everything else maps to its own init script if
# one exists. ac_reload_services skips any listed service whose init script is
# absent, so a not-installed entry is harmless. `system` needs `log` (logging
# settings) and `sysntpd` (the `ntp` timeserver) reloaded beyond
# /etc/init.d/system itself. An explicit --service overrides all of this.
ac_services_for() {
	local pkg s out="" seen=""
	for pkg in $1; do
		case "$pkg" in
			dhcp)     set -- dnsmasq odhcpd ;;
			wireless) set -- network ;;
			system)   set -- system log sysntpd ;;
			*)        if ac_init_exists "$pkg"; then set -- "$pkg"; else set --; fi ;;
		esac
		for s in "$@"; do
			case " $seen " in
				*" $s "*) ;;
				*) seen="$seen $s"; out="$out $s" ;;
			esac
		done
	done
	printf '%s' "${out# }"
}

ac_snapshot_pkg() {
	# $1 pkg, $2 dest dir. An absent/empty package exports nothing, which
	# round-trips correctly: importing it later clears the package, the true
	# restore of "this package had no config".
	local tmp="$2/$1.export.tmp"
	uci -q export "$1" > "$tmp" || { rm -f "$tmp"; return 6; }
	sync "$tmp" 2>/dev/null || sync
	mv "$tmp" "$2/$1.export"
}

ac_restore_pkg() {
	# $1 pkg, $2 snapshot file.
	uci -q import "$1" < "$2" || return 1
	uci -q commit "$1" || return 1
}

ac_reload_services() {
	# Reload, not restart, to minimize the management-link bounce while putting
	# the working config back.
	local rc=0 svc
	for svc in $1; do
		[ -x "/etc/init.d/$svc" ] || continue
		/etc/init.d/"$svc" reload >/dev/null 2>&1 || rc=1
	done
	return $rc
}

# The one thing the whole package exists to do. Idempotent: the lock plus the
# phase flip make a racing second caller (a respawned supervisor and the boot
# hook, say) a no-op. Returns 0 clean, 4 nothing-to-do, 5 restored-but-reload-
# failed.
ac_do_rollback() {
	local token="$1" f sd pkgs svcs pkg restore_rc=0 reload_rc=0
	f=$(ac_state_file "$token")
	[ -f "$f" ] || return 4

	exec 9>"$AC_LOCK"
	# Bounded wait: the lock only guards concurrent callers, and at boot there is
	# no contention, so this acquires at once. The timeout guarantees rollback can
	# never block forever on a wedged lock.
	flock -w 10 9 2>/dev/null || true
	if [ "$(ac_get_field "$f" phase)" != "armed" ]; then
		flock -u 9
		return 4
	fi

	sd=$(ac_get_field "$f" snapshot_dir)
	pkgs=$(ac_get_field "$f" packages)
	svcs=$(ac_get_field "$f" services)

	for pkg in $pkgs; do
		ac_restore_pkg "$pkg" "$sd/$pkg.export" || restore_rc=1
	done
	[ "$restore_rc" = 0 ] || ac_log "rollback: a uci import/commit failed for [$pkgs] (token $token)"

	ac_reload_services "$svcs" || reload_rc=1

	if [ "$reload_rc" != 0 ]; then
		# uci is already back to the prior config regardless of the reload result,
		# so leave it restored and never reinstate the broken change. Retain the
		# record for forensics.
		ac_set_phase "$token" rolledback_reload_failed
		ac_log "rolled back uci for [$pkgs] but a service reload failed (token $token)"
		flock -u 9
		return 5
	fi

	ac_set_phase "$token" rolledback
	ac_remove_record "$token"
	ac_log "rolled back [$pkgs] (token $token)"
	flock -u 9
	return 0
}
