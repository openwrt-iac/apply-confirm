# Boot recovery. Runs early from the init script's boot() and again from the NTP
# hotplug hook once the clock is trusted. Reconciles every persisted record
# against the decision table below.
#
# The load-bearing choice: an armed apply that survived a reboot was, by
# definition, never acked, and the operator was not present to ack it. A reboot
# mid-window is far more likely to mean "the change broke the box" than "all is
# well", so when the clock cannot be trusted we roll back. Failing safe.

ac_clock_trusted() { [ -f "$AC_CLOCK_TRUST" ]; }

ac_rearm() {
	# $1 token, $2 remaining seconds. Recompute the monotonic deadline against
	# this boot's uptime so a running supervisor counts down the real remainder.
	local up; up=$(ac_uptime)
	ac_set_field "$1" deadline_mono "$(( up + $2 ))"
}

ac_recover() {
	local f token phase now deadline
	for f in "$AC_STATE_DIR"/*.state; do
		[ -e "$f" ] || continue
		token=$(ac_get_field "$f" token)
		phase=$(ac_get_field "$f" phase)
		case "$phase" in
			committed|rolledback)
				ac_remove_record "$token" ;;
			rolledback_reload_failed)
				: ;;
			armed)
				if ac_clock_trusted; then
					now=$(ac_now)
					deadline=$(ac_get_field "$f" deadline)
					if [ "$now" -ge "$deadline" ]; then
						ac_log "boot: armed apply past deadline, rolling back (token $token)"
						ac_do_rollback "$token"
					else
						ac_log "boot: armed apply still in window, re-arming for $(( deadline - now ))s (token $token)"
						ac_rearm "$token" "$(( deadline - now ))"
					fi
				else
					case "$AC_REBOOT_POLICY" in
						rearm-on-trusted-clock)
							# Hold until the NTP hotplug hook re-runs recovery with a
							# trusted clock. Park the monotonic deadline far out so a
							# supervisor started now keeps polling instead of firing.
							ac_log "boot: clock untrusted, policy defers decision (token $token)"
							ac_set_field "$token" deadline_mono 9999999999 ;;
						*)
							ac_log "boot: clock untrusted, conservative rollback (token $token)"
							ac_do_rollback "$token" ;;
					esac
				fi ;;
		esac
	done
}
