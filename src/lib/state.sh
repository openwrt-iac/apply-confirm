# Durable state on the rw overlay. One file per token, line-oriented key=value so
# the boot hook parses it with nothing but the shell. Every mutation is a
# temp-write + rename, which is atomic within a filesystem: a reader never sees a
# torn file and a power cut leaves either the old file or the complete new one.
#
# Fields: token phase deadline deadline_mono packages services snapshot_dir pid
#         created reason
# phase:  armed -> committed | rolledback | rolledback_reload_failed

ac_state_file() { printf '%s/%s.state' "$AC_STATE_DIR" "$1"; }
ac_snap_dir()   { printf '%s/%s.d' "$AC_STATE_DIR" "$1"; }

ac_atomic_write() {
	# $1 dest path; content on stdin.
	local dest="$1" tmp="$1.$$.tmp"
	cat > "$tmp" || { rm -f "$tmp"; return 1; }
	sync "$tmp" 2>/dev/null || sync
	mv "$tmp" "$dest"
}

ac_get_field() {
	# $1 state file, $2 field. Parses without sourcing so a value can never run
	# as code. Splits on the first '=' only, so values may contain '=' or spaces.
	local k v
	[ -f "$1" ] || return 1
	while IFS='=' read -r k v; do
		[ "$k" = "$2" ] && { printf '%s' "$v"; return 0; }
	done < "$1"
	return 1
}

ac_set_field() {
	# $1 token, $2 field, $3 value. Read-modify-write via rename. Used for numeric
	# and enum fields (pid, phase, deadline_mono); not for free text.
	local f tmp; f=$(ac_state_file "$1"); tmp="$f.$$.tmp"
	if grep -q "^$2=" "$f" 2>/dev/null; then
		sed "s|^$2=.*|$2=$3|" "$f" > "$tmp"
	else
		{ cat "$f"; printf '%s=%s\n' "$2" "$3"; } > "$tmp"
	fi
	sync "$tmp" 2>/dev/null || sync
	mv "$tmp" "$f"
}

ac_set_phase() { ac_set_field "$1" phase "$2"; }

# The single armed token, or nothing. v0 allows one pending apply at a time, so
# this is the current apply under supervision.
ac_find_armed() {
	local f
	for f in "$AC_STATE_DIR"/*.state; do
		[ -e "$f" ] || continue
		if [ "$(ac_get_field "$f" phase)" = "armed" ]; then
			ac_get_field "$f" token
			return 0
		fi
	done
	return 1
}

ac_cleanup_snapshot() { rm -rf "$(ac_snap_dir "$1")"; }

ac_remove_record() {
	rm -rf "$(ac_snap_dir "$1")"
	rm -f "$(ac_state_file "$1")"
}
