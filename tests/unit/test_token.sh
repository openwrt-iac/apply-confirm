it "accepts a well-formed token"
assert_true ac_valid_token "ac_1718900000_a1b2c3d4"

it "rejects short hex"
assert_false ac_valid_token "ac_1718900000_a1b2c3"

it "rejects non-hex in the random field"
assert_false ac_valid_token "ac_1718900000_a1b2c3gz"

it "rejects a non-numeric time field"
assert_false ac_valid_token "ac_notime_a1b2c3d4"

it "rejects a shell-injection attempt"
assert_false ac_valid_token "ac_1_\$(rm -rf /)"

it "rejects empty"
assert_false ac_valid_token ""

it "a freshly minted token validates"
_t=$(ac_new_token)
assert_true ac_valid_token "$_t"
