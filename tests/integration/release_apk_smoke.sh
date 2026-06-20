#!/bin/sh
# Smoke-test the built APK in a fresh VM before it is published. Installs the
# package, exercises the stage/ack and stage/timeout-rollback cycles end to end,
# and checks the conffile survives a reinstall.
set -eu

APK_PATH=${1:-}
[ -n "$APK_PATH" ] || { echo "usage: $0 <path-to-apply-confirm.apk>"; exit 1; }
[ -f "$APK_PATH" ] || { echo "no such file: $APK_PATH"; exit 1; }

SSH="tests/vm/ssh.sh"
fail() { echo "FAIL: $*"; exit 1; }
push_file() { $SSH "cat > $2" < "$1"; }

echo "--- push and install the apk ---"
push_file "$APK_PATH" /tmp/apply-confirm.apk
$SSH 'apk add --allow-untrusted /tmp/apply-confirm.apk 2>&1 | tail -10'

echo "--- binary, init script, conffile, state dir present ---"
$SSH 'test -x /usr/sbin/apply-confirm' || fail "/usr/sbin/apply-confirm missing or not executable"
$SSH 'test -x /etc/init.d/apply-confirm' || fail "init script missing"
$SSH 'test -f /etc/config/apply-confirm' || fail "conffile missing"
$SSH 'test -d /etc/apply-confirm/pending' || fail "state dir not created by uci-defaults"

echo "--- stage then ack keeps the change ---"
orig=$($SSH "uci get system.@system[0].hostname")
TOKEN=$($SSH "apply-confirm stage --timeout 30 --package system") || fail "stage failed"
$SSH "apply-confirm status" | grep -q '^phase=armed' || fail "not armed after stage"
$SSH "uci set system.@system[0].hostname='smoke-ack'; uci commit system"
$SSH "apply-confirm ack '$TOKEN'" || fail "ack failed"
[ "$($SSH "uci get system.@system[0].hostname")" = "smoke-ack" ] || fail "acked change not kept"
$SSH "uci set system.@system[0].hostname='$orig'; uci commit system"

echo "--- stage then timeout rolls back ---"
$SSH "apply-confirm stage --timeout 3 --package system" >/dev/null || fail "stage failed"
$SSH "uci set system.@system[0].hostname='smoke-rollback'; uci commit system"
sleep 8
[ "$($SSH "uci get system.@system[0].hostname")" = "$orig" ] || fail "unconfirmed change not rolled back"

echo "--- conffile preserved across reinstall ---"
$SSH 'cp /etc/config/apply-confirm /tmp/ac.conf.before'
$SSH 'apk add --allow-untrusted --force-reinstall /tmp/apply-confirm.apk 2>&1 | tail -5 || apk add --allow-untrusted /tmp/apply-confirm.apk 2>&1 | tail -5'
$SSH 'cmp /etc/config/apply-confirm /tmp/ac.conf.before' || fail "conffile changed on reinstall"
$SSH 'rm -f /tmp/ac.conf.before'

echo "--- apk remove ---"
$SSH 'apk del apply-confirm 2>&1 | tail -5'
$SSH 'test ! -x /usr/sbin/apply-confirm' || fail "binary not removed on apk del"

echo "release apk smoke passed."
