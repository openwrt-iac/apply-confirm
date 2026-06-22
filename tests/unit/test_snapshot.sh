# AC_FAKE_RELOAD_RC is consumed by run_unit.sh's ac_reload_services override.
# shellcheck disable=SC2034
# Service-map derivation is covered in test_services.sh.

_arm() {
	# $1 token, writes an armed record snapshotting the current network config
	_sd=$(ac_snap_dir "$1"); mkdir -p "$_sd"
	ac_snapshot_pkg network "$_sd"
	ac_atomic_write "$(ac_state_file "$1")" <<EOF
token=$1
phase=armed
deadline=9999999999
deadline_mono=9999999999
packages=network
services=network
snapshot_dir=$_sd
pid=0
created=1
reason=test
EOF
}

it "do_rollback restores the snapshot and removes the record"
printf 'config-A' > "$SCRATCH/uci/network"
_t=$(ac_new_token); _arm "$_t"
printf 'config-B' > "$SCRATCH/uci/network"
AC_FAKE_RELOAD_RC=0
ac_do_rollback "$_t"; _rc=$?
assert_rc 0 "$_rc" "rollback rc"
assert_eq "config-A" "$(cat "$SCRATCH/uci/network")" "uci restored"

it "do_rollback on an already-resolved record is a no-op (rc 4)"
ac_do_rollback "$_t"; assert_rc 4 "$?"

it "do_rollback keeps uci restored but returns 5 when the reload fails"
printf 'config-A' > "$SCRATCH/uci/network"
_t=$(ac_new_token); _arm "$_t"
printf 'config-B' > "$SCRATCH/uci/network"
AC_FAKE_RELOAD_RC=1
ac_do_rollback "$_t"; _rc=$?
AC_FAKE_RELOAD_RC=0
assert_rc 5 "$_rc"
assert_eq "config-A" "$(cat "$SCRATCH/uci/network")"

it "a reload-failed rollback retains the record for forensics"
assert_eq "rolledback_reload_failed" "$(ac_get_field "$(ac_state_file "$_t")" phase)"
ac_remove_record "$_t"
