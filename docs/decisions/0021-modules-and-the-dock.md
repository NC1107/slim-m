# 0021 - Modules and the Dock

Status: accepted (design; implementation phased)
Date: 2026-09-06

## The ask

A space should be able to gain optional capabilities it does not ship with, installed by an admin from a marketplace, sourced from a single official second repository.
The first such capability is running code inside a space ("execute code blocks").
It must be off by default, reachable only when an admin goes to the marketplace and installs it.

## The core principle

slim provides the module *system*, never a module's behavior.

slim gains a general module host, a marketplace browser, an install/enable lifecycle, a dynamic permission registry, and a set of extension points.
It does not gain a single line that knows what "running code" is.
Running code lives entirely inside a module authored in the separate addons repository.
The test of the design is simple: with no module installed, slim has no notion of code execution at all, and deleting the module removes the capability and its permission cleanly.

This keeps the blast radius of every module contained, keeps slim's core small, and lets the risky, fast-moving parts (a language sandbox, say) evolve in their own repository on their own cadence without touching slim.

## Naming

The metaphor is a space station you dock modules to.

- A **Module** is an installable addon.
- **The Dock** is the marketplace: where an admin browses, searches, and installs modules.
- Installing is "docking a module" to the space; removing is "undocking".

The Dock lives under space settings, gated on `MANAGE_SERVER`, alongside analytics, retention, and storage.

## What lives where

slim (this repo) owns:

- The **module host**: loads installed modules, routes extension-point events to them, enforces their granted capabilities. (Runtime; a later phase.)
- **The Dock**: fetches and searches the addons repo's index, shows a module's manifest and what it asks for, before anything is installed.
- The **install/enable/uninstall lifecycle**, per space, admin-gated, version-pinned, off by default.
- The **dynamic permission registry**: module-declared permissions that appear in the space's role/permission UI on install and disappear on uninstall.
- The **runtime backends** a module can request (WASM first; see below). A backend is host infrastructure, not a module.
- The **extension-point contracts** modules plug into.

The addons repo (`slim-addons`, separate) owns:

- Every module's manifest and artifact, including the code-execution module and, inside it, everything about how code runs.

## The module manifest

A module is described by a `manifest.json` the Dock reads before install and the host reads to wire it up.
Shape (illustrative, finalized in the marketplace phase):

```json
{
  "id": "code-exec",
  "name": "Code Blocks",
  "version": "1.2.0",
  "summary": "Run code snippets in a channel and post the output.",
  "author": "slim-m",
  "artifact": { "kind": "wasm", "path": "modules/code-exec/1.2.0/module.wasm", "sha256": "..." },
  "runtime": { "backend": "wasm", "limits": { "memory_mb": 64, "wall_ms": 2000, "fuel": 500000000 } },
  "permissions": [
    { "key": "run", "name": "Execute code blocks", "description": "Submit a snippet to run in this space." }
  ],
  "capabilities": ["command.register", "message.post", "kv.store"],
  "extension_points": [
    { "kind": "command", "name": "run", "description": "Run a code snippet." }
  ]
}
```

Notes on each part:

- `permissions` are **declared by the module**, namespaced by its id (`code-exec:run`).
  On install they are registered into the space's permission registry and become grantable to roles.
  This is how "Execute code blocks" appears in the space without slim ever hardcoding it.
- `capabilities` are what the module asks the *host* for.
  The admin sees and approves them at install; the host refuses any host call outside the granted set (no ambient authority).
- `runtime.backend` names a host-provided backend the module needs.
  The module never ships or installs a runtime; it requests one slim already offers.
- `extension_points` are the slim-defined seams the module attaches to (a command, a message action, a scheduled job, a settings panel). The first release defines `command` only.

## Dynamic permissions

slim's core permissions are a fixed bitmask.
Module permissions cannot be compile-time bits, because slim must not know them.
So installed modules register **named, module-scoped permissions** (strings like `code-exec:run`) into a registry stored in the database.

- They appear in the role/permission editor as ordinary grantable rows, labeled by the module.
- The module host checks them at runtime when a module asks "may this user do X" - the module never sees a raw bitmask, only a yes/no for its own declared key.
- Uninstalling a module removes its permission rows and any grants of them, so nothing dangles.

This is the one real extension slim's permission model needs, and it is general: it serves every future module, not just code execution.

## The security and trust model

Code from a repository running inside a space is the whole risk, so isolation is the design, not an afterthought.

- **Source is one official, curated repository, pinned.** A module is installed at an exact version and its artifact is verified against the `sha256` in the manifest.
  Third-party or arbitrary repositories are out of scope for the first design; if ever added, they are a separate, later decision with its own review.
- **The fetch itself is guarded.** The Dock reaches GitHub over a host-allowlisted client (raw.githubusercontent.com / api.github.com for the one repo), the same posture as decision 0019's SSRF defense, so the marketplace cannot be pointed at an internal address.
- **No ambient authority.** A module gets exactly the host capabilities its manifest declared and the admin approved, nothing else. Network egress from a module is default-deny.
- **The runtime is sandboxed** (see below). A module cannot touch slim's process memory, the database, the host filesystem, or the network except through granted, mediated host calls.
- **Everything is per space and reversible.** Off by default, install is an explicit admin act, uninstall is clean, and every install/enable/grant is auditable through the existing moderation-audit trail (decision 0015).

## Runtime backends

A backend is provided by slim; a module declares which one it needs.

- **WASM first (`wasmtime`).** Runs in slim's process but strongly isolated: no syscalls, memory-bounded, CPU and time metered by fuel, network default-deny.
  It fits slim's single-process, self-hostable identity and needs no extra service.
  A module that must run a *language* (the code-exec module running user snippets) does so by carrying a language runtime compiled to WASM (for example QuickJS for JavaScript); that choice is the module's, not slim's.
- **A container backend is a possible later host capability, not a module.**
  It would give OS-level isolation and native language support at the cost of a second service and real ops.
  Deferred; recorded here because the shape of the manifest (`runtime.backend`) already allows a module to request it without any change to the module model.

This is the answer to "how would a docker executor get installed from the marketplace": it would not.
The executor is host infrastructure; the marketplace installs modules, and a module only names the backend it wants.

## The marketplace protocol

- The addons repo publishes `index.json` at its root: a list of `{ id, name, version, summary }`.
- Each module has `modules/<id>/manifest.json` and its artifact under a version path, pinned by release tag or commit sha.
- The Dock fetches the index, lets an admin search it, and shows a chosen module's full manifest, including the permissions it will add and the capabilities it asks for, before any install.

## Lifecycle

1. Admin opens the Dock (space settings, `MANAGE_SERVER`).
2. Searches the index, opens a module, reviews its declared permissions and requested capabilities.
3. Installs at a pinned version: slim fetches and verifies the artifact, records the install for this space, registers the module's permissions, and stores the approved capability set.
4. The new permission(s) now appear in the role editor; the admin grants them to roles as desired.
5. Enable/disable toggles the module without losing its config; uninstall removes it, its permissions, and their grants.

Nothing here runs module code yet; that is the runtime phase.

## The code-execution module

Authored in `slim-addons`, not here.
It declares one permission (`code-exec:run`, "Execute code blocks"), one `command` extension point ("run"), and the `wasm` runtime backend.
Its command takes a snippet, runs it in the sandbox its own bundled language runtime provides, and posts the output through the `message.post` capability.
slim contains none of this; it only routes the command to the module and enforces the permission and capabilities.

## Phasing

- **Phase 1 - the Dock (browse).** Admin-only marketplace that fetches and searches the addons repo's index and shows a module's manifest, permissions, and capabilities. Read-only; nothing installed. Proves the fetch, the allowlist, and the manifest contract.
- **Phase 2 - install and dynamic permissions (no runtime).** Install/enable/uninstall a module per space, version-pinned and artifact-verified; register module permissions into the space so "Execute code blocks" appears and is grantable; store approved capabilities. No execution yet. **This plus Phase 1 is the first build.**
- **Phase 3 - the module host and WASM backend.** Load installed modules, route extension-point events, enforce capabilities, run WASM under strict limits.
- **Phase 4 - the code-execution module.** Authored in `slim-addons`, consuming Phases 1 to 3. The first end-to-end proof that a real capability lives entirely in a module.
- **Phase 5 - hardening.** Rate limits, per-module resource accounting, audit surfacing, and a considered look at whether a container backend is worth its ops cost.

## Decisions (owner, 2026-09-06)

- **Repository:** `NC1107/slim-addons`, public, default branch `main`. The Dock fetches `https://raw.githubusercontent.com/NC1107/slim-addons/main/index.json` and per-module manifests under it. Created with the code-exec manifest already present.
- **First language:** JavaScript, via a QuickJS build compiled to WASM that the code-exec module carries. slim itself stays language-agnostic.
- **Permissions:** space-wide for the first pass; channel-scoped overwrites for module permissions are a later extension.
- **Integrity:** sha256 pin only for now; an artifact signature is a later hardening (Phase 5).
- **WASM engine:** `wasmi` (pure-Rust interpreter, small binary footprint, supports fuel metering) rather than `wasmtime`, to protect the 20 MiB release-binary budget the brief treats as first-class. `wasmtime` is the upgrade path if execution speed becomes the bottleneck; the `runtime.backend` field already lets a module stay indifferent to which the host uses.
