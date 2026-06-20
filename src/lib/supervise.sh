# The live countdown. Launched by procd for the armed apply. Sleeps toward the
# monotonic deadline in bounded chunks so an ack (which flips phase away from
# armed, or removes the record) is noticed within one chunk and the process
# exits promptly. Re-reads deadline_mono every wake so a boot-time re-arm is
# picked up by an already-running supervisor.

AC_SUPERVISE_CHUNK="${AC_SUPERVISE_CHUNK:-5}"

ac_supervise() {
	local token f dm up phase remain
	token="${1:-}"
	[ -n "$token" ] || token=$(ac_find_armed) || return 0
	[ -n "$token" ] || return 0
	f=$(ac_state_file "$token")
	[ -f "$f" ] || return 0

	ac_set_field "$token" pid "$$"

	while :; do
		[ -f "$f" ] || return 0
		phase=$(ac_get_field "$f" phase) || return 0
		[ "$phase" = "armed" ] || return 0
		dm=$(ac_get_field "$f" deadline_mono) || return 0
		up=$(ac_uptime)
		[ "$up" -ge "$dm" ] && break
		remain=$(( dm - up ))
		[ "$remain" -gt "$AC_SUPERVISE_CHUNK" ] && remain="$AC_SUPERVISE_CHUNK"
		sleep "$remain"
	done

	ac_do_rollback "$token"
}
