# apply-confirm

A commit-confirmed-apply rollback supervisor for OpenWrt. Stage a config change
with a deadline; if it is not acked in time, restore the pre-change snapshot and
reload services to the prior state. The rollback must fire locally and survive a
reboot, a process kill, and a broken management interface.

This is a standalone OpenWrt package, not part of uapi. uapi 3.x and LuCI
integrate by invoking the CLI. The name `apply-confirm` is a working placeholder
pending the design issue.

## What this is, in one invariant

**An armed apply that is not acked gets its pre-apply snapshot restored, across a
reboot, a supervisor kill, or a broken management interface.** Every design
choice serves that. Failing wrong (leaving an unconfirmed change live) is the
cardinal sin; this is a safety primitive, not an HTTP handler.

## Principles (non-negotiable)

1. **Fail safe, not closed.** When the state is ambiguous (clock untrusted after
   a reboot, supervisor died, reload failed during restore), choose the action
   that ends with the operator's prior, known-working config in place.
2. **The trigger is local.** Firing a rollback must never depend on the network,
   on rpcd's session, or on the supervisor process staying alive. The network
   breaking is the expected condition, not a failure mode.
3. **Durable over clever.** State that must survive a reboot lives on the rw
   overlay (`/etc`), is written atomically (temp + rename), and is parseable by a
   boot hook with zero dependencies.
4. **Zero-bloat footprint.** Target is a 32MB-RAM router. Shell + procd only. No
   new daemons, no compiled deps beyond what OpenWrt already ships.

## Code and documentation style

- **Priorities, in order:** simplicity, maintainability, modularity, readability.
- **POSIX sh / busybox ash only.** No bashisms. Test against the OpenWrt VM, not
  a desktop bash.
- **No em-dashes.** Code, comments, docs, commit messages.
- **Comments are rare and explain why, not what.** A load-bearing why-comment
  (a non-obvious invariant, an ordering constraint, an upstream workaround) stays.
  Anything a competent reader reads off the code is slop; delete it.
- **No narration headers, no ceremonial echoes, no one-call-site helpers** unless
  the name carries non-obvious meaning.

## Discipline (heavier than a normal package)

This is a safety primitive, so release discipline is stricter than uapi's:

- **RC first, always.** Even minor releases soak as `-rc` before final. No
  ship-as-patch-direct.
- **The acceptance test is `07_broken_mgmt_iface`.** A change that cannot keep
  that test green does not merge.
- **Branch + PR only**, never direct push to `main`. Org-wide rule.

## Layout

| Path | Role |
|------|------|
| `src/apply-confirm` | CLI dispatcher (installed `/usr/sbin/apply-confirm`) |
| `src/lib/common.sh` | config load, paths, logging, token validation |
| `src/lib/state.sh` | atomic state read/write |
| `src/lib/snapshot.sh` | snapshot / restore / reload / do_rollback |
| `src/lib/supervise.sh` | monotonic sleep loop |
| `src/lib/recover.sh` | boot recovery decision table, clock trust |
| `files/etc/init.d/apply-confirm` | procd service: boot recovery + supervise |
| `files/etc/config/apply-confirm` | conffile (default timeout, paths, policy) |
| `files/etc/hotplug.d/ntp/20-apply-confirm` | mark clock trusted on NTP sync |
| `build/openwrt/apply-confirm/Makefile` | OpenWrt package Makefile |
| `docs/` | architecture, cli-contract, hardening, rpcd-apply-path, testing, packaging |

## Where the details live

| Topic | File |
|-------|------|
| State file, durable timer, boot recovery table | `docs/architecture.md` |
| CLI subcommands, exit codes, token format, 3-caller validation | `docs/cli-contract.md` |
| Broken-mgmt scenario, ordering, fallbacks, risks | `docs/hardening.md` |
| What rpcd does and what we do differently | `docs/rpcd-apply-path.md` |
| Test layers and the hard scenarios | `docs/testing.md` |
| Package build and release | `docs/packaging.md` |
