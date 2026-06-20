_tok="ac_1000_aaaaaaaa"
_f=$(ac_state_file "$_tok")
printf 'token=%s\nphase=armed\npackages=network firewall\npid=0\n' "$_tok" | ac_atomic_write "$_f"

it "atomic_write then get_field round-trips a field"
assert_eq "armed" "$(ac_get_field "$_f" phase)"

it "get_field preserves spaces in a value"
assert_eq "network firewall" "$(ac_get_field "$_f" packages)"

it "set_field updates an existing field"
ac_set_field "$_tok" phase committed
assert_eq "committed" "$(ac_get_field "$_f" phase)"

it "set_field appends a missing field"
ac_set_field "$_tok" deadline_mono 12345
assert_eq "12345" "$(ac_get_field "$_f" deadline_mono)"

it "find_armed returns the armed record, not the committed one"
_tok2="ac_2000_bbbbbbbb"
_f2=$(ac_state_file "$_tok2")
printf 'token=%s\nphase=armed\n' "$_tok2" | ac_atomic_write "$_f2"
assert_eq "$_tok2" "$(ac_find_armed)"

it "remove_record deletes the state file"
ac_remove_record "$_tok2"
assert_false test -f "$_f2"

ac_remove_record "$_tok"
