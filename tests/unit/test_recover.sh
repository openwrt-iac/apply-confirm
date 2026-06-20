it "clock_trusted reflects the flag file"
rm -f "$AC_CLOCK_TRUST"
assert_false ac_clock_trusted
touch "$AC_CLOCK_TRUST"
assert_true ac_clock_trusted

it "rearm sets deadline_mono to uptime plus the remaining window"
_t=$(ac_new_token); _f=$(ac_state_file "$_t")
printf 'token=%s\nphase=armed\ndeadline_mono=0\n' "$_t" | ac_atomic_write "$_f"
ac_rearm "$_t" 100
_up=$(ac_uptime)
_dm=$(ac_get_field "$_f" deadline_mono)
_diff=$(( _dm - _up - 100 )); [ "$_diff" -lt 0 ] && _diff=$(( -_diff ))
assert_true test "$_diff" -le 2
ac_remove_record "$_t"

_arm_at() {
	# $1 token, $2 absolute deadline, $3 monotonic deadline
	_sd=$(ac_snap_dir "$1"); mkdir -p "$_sd"
	ac_snapshot_pkg network "$_sd"
	ac_atomic_write "$(ac_state_file "$1")" <<EOF
token=$1
phase=armed
deadline=$2
deadline_mono=$3
packages=network
services=network
snapshot_dir=$_sd
pid=0
created=1
reason=test
EOF
}

it "recover rolls back an armed apply past its deadline (trusted clock)"
touch "$AC_CLOCK_TRUST"
printf 'config-A' > "$SCRATCH/uci/network"
_t=$(ac_new_token); _arm_at "$_t" 1 1
printf 'config-B' > "$SCRATCH/uci/network"
ac_recover boot
assert_eq "config-A" "$(cat "$SCRATCH/uci/network")"
assert_false test -f "$(ac_state_file "$_t")"

it "recover rolls back conservatively when the clock is untrusted"
rm -f "$AC_CLOCK_TRUST"
printf 'config-A' > "$SCRATCH/uci/network"
_t=$(ac_new_token); _arm_at "$_t" 9999999999 9999999999
printf 'config-B' > "$SCRATCH/uci/network"
ac_recover boot
assert_eq "config-A" "$(cat "$SCRATCH/uci/network")"
ac_remove_record "$_t" 2>/dev/null

it "recover re-arms an armed apply still in window (trusted clock)"
touch "$AC_CLOCK_TRUST"
_now=$(ac_now)
_t=$(ac_new_token); _arm_at "$_t" "$(( _now + 100 ))" 1
ac_recover boot
assert_eq "armed" "$(ac_get_field "$(ac_state_file "$_t")" phase)"
ac_remove_record "$_t"
