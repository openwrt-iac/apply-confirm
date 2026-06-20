# Tiny sh test harness. Sourced by run_unit.sh; test files call it() then an
# assert. Mirrors uapi's homegrown harness in spirit: no framework, exit 1 on
# any failure.

AC_TESTS_RUN=0
AC_TESTS_FAIL=0
_cur=""

it() { _cur="$1"; AC_TESTS_RUN=$((AC_TESTS_RUN + 1)); }
_ok()   { printf 'ok - %s\n' "$_cur"; }
_fail() { AC_TESTS_FAIL=$((AC_TESTS_FAIL + 1)); printf 'not ok - %s: %s\n' "$_cur" "$1"; }

assert_eq() { if [ "$1" = "$2" ]; then _ok; else _fail "${3:-} expected [$1] got [$2]"; fi; }
assert_rc() { if [ "$1" = "$2" ]; then _ok; else _fail "${3:-} expected rc [$1] got [$2]"; fi; }
assert_true()  { if "$@"; then _ok; else _fail "expected success: $*"; fi; }
assert_false() { if "$@"; then _fail "expected failure: $*"; else _ok; fi; }
