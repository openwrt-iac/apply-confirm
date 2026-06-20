# Design issue (draft, not yet filed)

> File this in the new repo's tracker (or on `openwrt-iac/uapi#3` until the repo
> exists) to gather field input before locking v0. The answers below are the
> working defaults the prototype already assumes; this issue asks the field to
> confirm or revise them, not to start from scratch.

---

**Title:** commit-confirmed-apply: design decisions and naming

OpenWrt lacks a reboot-surviving commit-confirmed-apply primitive. rpcd's
`uci.apply {rollback,timeout}` is close but its rollback state is in-memory, has a
90s floor, allows one global pending apply, and does not survive a reboot (see
`docs/rpcd-apply-path.md`). This is the gap that locks operators out when a
config push breaks the only path to the box.

We are building a standalone package for it. Three decisions and the name need
field input before we lock v0.

## 1. Ack channel

How does the operator confirm the change is good?

- **(working default) Same network the change touched, with a local CLI ack /
  rollback fallback that always works without network.** Matches reality (the
  operator usually has one path) while keeping a console escape hatch.
- Local-only ack: safest, but does not help a remote operator, the main case.
- Separate management channel: cleanest, but assumes OOB access most lack.

What do JunOS / IOS / OPNsense operators expect here? Does the local fallback
cover your recovery story?

## 2. Relationship to rpcd's `uci.apply`

- **(working default) Independent supervisor** with its own durable snapshot +
  timer + boot recovery. Reuses rpcd's vocabulary, not its session.
- Extend rpcd upstream: heavier, slower to iterate.
- Thin wrapper over rpcd: inherits the no-reboot-survival limit.

Is there appetite to eventually upstream this into rpcd, or should it stay a
separate primitive? Any coexistence concern with LuCI's existing apply flow?

## 3. CLI / IPC contract

Proposed contract in `docs/cli-contract.md`: `stage` (returns a token), `ack`,
`rollback`, `status`, `list`, with a documented exit-code table. Validated
against three callers (raw shell, LuCI, uapi). Does it drive cleanly for your
caller? If only one caller drives it cleanly, the contract is wrong; tell us
which fields or commands are awkward.

## 4. Name

Working name `apply-confirm` (uses uci's own `apply` / `confirm` / `rollback`
verbs, no `u`-prefix, matches the `apply_confirm: true` flag uapi would set).
Standalone identity matters if this ever becomes the canonical OpenWrt primitive,
so it is deliberately not uapi-prefixed. Alternatives considered: `owrt-confirm`,
`uci-confirm-apply`, `apply-watch`. Preferences?
