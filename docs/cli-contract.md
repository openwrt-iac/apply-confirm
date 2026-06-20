# CLI / IPC contract

The shell-visible API. This is the contract callers depend on; internals may
change, this should not without a version bump. Binary: `/usr/sbin/apply-confirm`.

## Subcommands

```
apply-confirm stage [--timeout N] --package PKG [--package PKG...] [--service SVC...] [--reason TEXT]
apply-confirm ack TOKEN
apply-confirm rollback [TOKEN]
apply-confirm status [TOKEN] [--json]
apply-confirm list [--json]
```

### stage

Snapshots the named packages, computes the deadline, writes durable state, brings
up the supervisor, and prints the **token to stdout and nothing else**. The
caller applies its change after a successful stage.

- `--timeout N` seconds, default from `default_timeout` (90), clamped to
  `max_timeout` (3600).
- `--package PKG` repeatable, at least one required. These are the uci packages
  snapshotted and restored on rollback.
- `--service SVC` repeatable, optional. Services reloaded on rollback. Defaults
  to the packages' tracked services (`network`->network, `firewall`->firewall,
  `dhcp`->dnsmasq+odhcpd, others to themselves).
- `--reason TEXT` optional, recorded for forensics.
- Refuses with **exit 3** if an apply is already armed (one pending apply at a
  time). On a snapshot failure it exits **6** without arming, so the caller must
  check the exit code and not proceed with its change if stage failed.

### ack

Confirms the armed apply: the change is good, keep it. Verifies the token,
flips the phase to committed, and deletes the snapshot. **Exit 4** if the token
does not match an armed apply (it never existed, or the window already closed
and the change was rolled back). The 0-vs-4 result is the single most important
return value: it tells the caller whether the box kept the change.

### rollback

Operator-initiated immediate rollback, the console escape hatch. With a token,
validates it; without one, acts on the single pending apply. Needs no network
and no daemon. **Exit 5** if the snapshot was restored but a service reload
failed (uci is still back to the prior config).

### status / list

`status` prints the pending apply including `remaining` seconds (from the
monotonic clock); `--json` for programmatic callers. **Exit 4** if nothing is
pending. `list` shows all records including retained terminal-phase ones
(rolled-back-with-failed-reload) for forensics.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | success |
| 2 | usage / bad arguments / malformed token |
| 3 | already armed (stage refused) |
| 4 | no such token / window already closed / nothing pending |
| 5 | rollback restored uci but a service reload failed |
| 6 | internal error (snapshot or state write failed; nothing armed) |

## Token format

`ac_<unixtime>_<8 lowercase hex>`, e.g. `ac_1718900000_a1b2c3d4`. Validated
against `^ac_[0-9]+_[0-9a-f]{8}$` on every `ack`/`rollback` so a token can never
reach a path or a sed expression as injection. The time prefix aids forensics;
the random suffix stops a stale token from a prior arm being re-acked.

## Validated against three callers

The contract is wrong if only uapi drives it cleanly. It must serve all three:

**Raw shell / SSH operator.**
```sh
TOKEN=$(apply-confirm stage --timeout 60 --package network)
# apply the change (uci set; uci commit; /etc/init.d/network reload)
apply-confirm ack "$TOKEN"        # if still reachable
```
Locked out? On the console, with no network: `apply-confirm rollback`. The token
on stdout is directly capturable; the fallback needs nothing but a local shell.

**LuCI.** Drives the same CLI from its ucode controller and polls
`apply-confirm status --json` for `remaining` to render the countdown it already
shows for rpcd's confirm flow. Gains the reboot survival rpcd lacks.

**uapi 3.x.** Invokes the CLI from its handler, captures the token, threads it
through its transaction, and calls `ack` after its own validate+commit+reload
succeeds. Exit 3/4/5 map onto its error envelope (`already_armed`,
`confirm_window_closed`, `rollback_reload_failed`). uapi integrates by invoking,
never by absorbing.

A console operator with a dead network fully driving this with two no-argument
commands is the proof the contract is not HTTP-shaped.
