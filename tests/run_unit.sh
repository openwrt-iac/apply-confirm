#!/bin/sh
# Unit runner. Sources the libs into a scratch environment with a fake uci so
# the pure logic and the rollback path can be exercised without a router.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

export AC_TEST=1
export AC_STATE_DIR="$SCRATCH/pending"
export AC_LOCK="$SCRATCH/lock"
export AC_CLOCK_TRUST="$SCRATCH/clock-trusted"
export AC_DEFAULT_TIMEOUT=90
export AC_MAX_TIMEOUT=3600
export AC_REBOOT_POLICY=rollback
mkdir -p "$AC_STATE_DIR" "$SCRATCH/uci"

# Fake uci: per-package config is a file under $SCRATCH/uci. export prints it,
# import overwrites it, commit is a no-op. Enough to verify snapshot/restore.
uci() {
	[ "$1" = "-q" ] && shift
	case "$1" in
		export) [ -f "$SCRATCH/uci/$2" ] && cat "$SCRATCH/uci/$2"; return 0 ;;
		import) cat > "$SCRATCH/uci/$2"; return 0 ;;
		commit) return 0 ;;
		*) return 0 ;;
	esac
}

. "$ROOT/tests/unit/harness.sh"
. "$ROOT/src/lib/common.sh"
. "$ROOT/src/lib/state.sh"
. "$ROOT/src/lib/snapshot.sh"
. "$ROOT/src/lib/supervise.sh"
. "$ROOT/src/lib/recover.sh"

# Override the real init.d reload with a controllable stub. Tests set
# AC_FAKE_RELOAD_RC to drive the restored-but-reload-failed path.
AC_FAKE_RELOAD_RC=0
ac_reload_services() { return "$AC_FAKE_RELOAD_RC"; }

# The service map's same-name fallback checks /etc/init.d/<pkg>, which does not
# exist on the dev host. Stub it with a fixed "installed" set so the map is
# testable host-independently.
AC_FAKE_INITS="network firewall dropbear system log sysntpd dnsmasq odhcpd"
ac_init_exists() { case " $AC_FAKE_INITS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

export SCRATCH
for t in "$ROOT"/tests/unit/test_*.sh; do
	# shellcheck disable=SC1090
	. "$t"
done

printf '\n%d run, %d failed\n' "$AC_TESTS_RUN" "$AC_TESTS_FAIL"
[ "$AC_TESTS_FAIL" = 0 ]
