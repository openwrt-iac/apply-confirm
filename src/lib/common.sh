# Paths, config, logging, and token helpers. Sourced by the CLI, the supervisor,
# the recovery hook, and the unit tests. POSIX sh / busybox ash only.
#
# Every AC_* path is overridable from the environment so the unit tests can run
# against a scratch directory with AC_TEST=1 and never touch a real router.

AC_NAME="apply-confirm"

ac_config() {
	# $1 option, $2 default. Reads uci unless AC_TEST is set (tests have no uci).
	local v=""
	[ -n "${AC_TEST:-}" ] || v=$(uci -q get "${AC_NAME}.main.$1" 2>/dev/null)
	[ -n "$v" ] && printf '%s' "$v" || printf '%s' "$2"
}

AC_STATE_DIR="${AC_STATE_DIR:-$(ac_config state_dir /etc/apply-confirm/pending)}"
AC_LOCK="${AC_LOCK:-/var/lock/apply-confirm.lock}"
# Clock-trust is a per-boot runtime flag on tmpfs: absent until sysntpd syncs,
# which is exactly the "do not trust the wall clock yet" signal the boot hook
# needs after a reboot with no RTC.
AC_CLOCK_TRUST="${AC_CLOCK_TRUST:-/var/run/apply-confirm.clock-trusted}"
AC_DEFAULT_TIMEOUT="${AC_DEFAULT_TIMEOUT:-$(ac_config default_timeout 90)}"
AC_MAX_TIMEOUT="${AC_MAX_TIMEOUT:-$(ac_config max_timeout 3600)}"
AC_REBOOT_POLICY="${AC_REBOOT_POLICY:-$(ac_config reboot_policy rollback)}"

ac_log() {
	logger -t "$AC_NAME" "$*" 2>/dev/null
	[ -t 2 ] && printf '%s\n' "$*" >&2
	return 0
}

ac_now() { date +%s; }

# Monotonic seconds since boot. Immune to wall-clock jumps when sysntpd syncs,
# which is why the live countdown measures against this and not date +%s.
ac_uptime() { local u _; read -r u _ < /proc/uptime; printf '%s' "${u%.*}"; }

ac_new_token() {
	local rnd
	rnd=$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')
	printf 'ac_%s_%s' "$(ac_now)" "$rnd"
}

# Reject anything that is not ac_<digits>_<8 lowercase hex> before it reaches a
# path or a sed expression.
ac_valid_token() {
	local t="$1" ts hex
	case "$t" in ac_*_*) ;; *) return 1 ;; esac
	ts=${t#ac_}; ts=${ts%_*}
	hex=${t##*_}
	case "$ts" in ''|*[!0-9]*) return 1 ;; esac
	case "$hex" in
		[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) return 0 ;;
		*) return 1 ;;
	esac
}
