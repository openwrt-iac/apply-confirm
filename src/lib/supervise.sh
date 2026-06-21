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
	while :; do
		token=$(ac_find_armed 2>/dev/null) || token=""
		if [ -z "$token" ]; then
			sleep "$AC_IDLE_POLL"
			continue
		fi

		f=$(ac_state_file "$token")
		ac_set_field "$token" pid "$$"

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
