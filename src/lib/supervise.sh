# The supervisor daemon. A single long-lived process: it watches for an armed
# apply, counts down to its deadline against the monotonic clock, rolls back if
# the deadline passes while still armed, then goes back to watching. It never
# exits on its own, so procd keeps exactly one instance and only respawns it on
# an actual crash. (An earlier design exited when idle and relied on procd
# respawn, which storm-respawned every few seconds after every apply and starved
# a slow box.)

AC_SUPERVISE_CHUNK="${AC_SUPERVISE_CHUNK:-5}"
AC_IDLE_POLL="${AC_IDLE_POLL:-2}"

ac_supervise() {
	local token f dm up phase remain
	# Reconcile any apply that survived a reboot before watching, so this one
	# daemon owns both recovery and supervision. Doing recovery here (not in a
	# separate boot-time pass) avoids a race where a concurrent recover removes a
	# record while this loop is stamping its pid, which left a zombie armed record.
	# Gate on a per-boot tmpfs marker so a mid-uptime respawn just resumes (else
	# an untrusted clock would make a respawn roll back an in-window apply).
	if [ ! -e "$AC_RECOVERED_FLAG" ]; then
		ac_recover boot
		: > "$AC_RECOVERED_FLAG" 2>/dev/null || true
	fi
	while :; do
		token=$(ac_find_armed 2>/dev/null) || token=""
		if [ -z "$token" ]; then
			sleep "$AC_IDLE_POLL"
			continue
		fi

		f=$(ac_state_file "$token")
		# Stamp our pid under the lock, and only while still armed, so a
		# concurrent ack/rollback removal (which holds the same lock) cannot be
		# followed by ac_set_field re-creating the record into a zombie.
		exec 9>"$AC_LOCK"
		flock -w 10 9 2>/dev/null || true
		if [ -f "$f" ] && [ "$(ac_get_field "$f" phase)" = "armed" ]; then
			ac_set_field "$token" pid "$$"
		fi
		flock -u 9

		# Count this armed apply down to its deadline. Bounded chunks so an ack
		# (phase flips, or the record is removed) is noticed within one chunk and
		# deadline_mono re-arms are picked up.
		while :; do
			[ -f "$f" ] || break
			phase=$(ac_get_field "$f" phase) || break
			[ "$phase" = "armed" ] || break
			dm=$(ac_get_field "$f" deadline_mono) || break
			up=$(ac_uptime)
			if [ "$up" -ge "$dm" ]; then
				ac_do_rollback "$token"
				break
			fi
			remain=$(( dm - up ))
			[ "$remain" -gt "$AC_SUPERVISE_CHUNK" ] && remain="$AC_SUPERVISE_CHUNK"
			sleep "$remain"
		done
	done
}
