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
  A module that must run a *language* (the code-exec module running user snippets) does so by carrying a language runtime compiled to WASM (the code-exec module uses the pure-Rust `boa` JS engine, which compiles import-free; QuickJS would need WASI imports the ABI forbids); that choice is the module's, not slim's.
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
- **First language:** JavaScript, via the pure-Rust `boa` engine compiled to import-free WASM that the code-exec module carries (chosen over QuickJS/javy, which require WASI imports the ABI forbids; both are JS). slim itself stays language-agnostic.
- **Permissions:** space-wide for the first pass; channel-scoped overwrites for module permissions are a later extension.
- **Integrity:** sha256 pin only for now; an artifact signature is a later hardening (Phase 5).
- **WASM engine:** `wasmi` (pure-Rust interpreter, small binary footprint, supports fuel metering) rather than `wasmtime`, to protect the 20 MiB release-binary budget the brief treats as first-class. `wasmtime` is the upgrade path if execution speed becomes the bottleneck; the `runtime.backend` field already lets a module stay indifferent to which the host uses.

## Module ABI v1

Phase 3's host (`crate::module_runtime::ModuleHost`) runs a module under a
deliberately minimal ABI, kept import-free for maximal isolation: a module is
pure compute in v1, nothing more.

A module exports exactly two functions and one memory, and imports nothing:

- `memory` (exported linear memory).
- `alloc(len: i32) -> i32`: reserves `len` bytes inside the module's own
  memory and returns a pointer. Called once by the host, before `run`, to get
  somewhere to write the request.
- `run(in_ptr: i32, in_len: i32) -> i64`: given the request the host just
  wrote at `in_ptr`/`in_len`, returns a packed `(out_ptr << 32) | out_len`
  pointing at the response, wherever the module put it.

The host writes a UTF-8 JSON request into the memory `alloc` returned, calls
`run`, and reads `out_len` bytes at `out_ptr` back as a UTF-8 JSON response.
Request: `{ "command": "<name>", "input": "<string>" }`. Response:
`{ "ok": true, "output": "<string>" }` or `{ "ok": false, "error": "<string>" }`.
That JSON shape is a contract between `http::module_commands` and the
module; the host itself only moves bytes and has no opinion about what is
inside them.

The host refuses to instantiate a module that declares any wasm import at
all, and refuses one whose artifact sha256 does not match what was recorded
at install. No imports means a module can only compute - it cannot touch the
network, the filesystem, or anything else in the host process. Every other
capability a module might eventually want (posting a message, reading a
key-value store) has to arrive later as an explicit, mediated host function
per the "no ambient authority" principle above, never as ambient access.

Each call runs under the manifest's own `runtime.limits`: a memory cap
(enforced via wasmi's `ResourceLimiter`), a fuel cap (CPU, via wasmi's fuel
metering), and a wall-clock cap (the call runs on a blocking task under a
timeout, abandoned rather than awaited past the deadline). Any of the three
being hit answers with a clean `{ "ok": false, "error": ... }`, never a 500
and never a hang.

The install flow now also fetches the module's own artifact bytes (over the
same host-allowlisted client the manifest itself came from), verifies them
against the manifest's `sha256`, and stores them - Phase 2 had deferred this;
Phase 3 needs the bytes to actually run something. They are kept as a
database row rather than a media-style file: unlike attachments, a module
artifact is one of a handful installed deployment-wide, bounded in size at
fetch time, and versioned with the install row it belongs to, so there is no
attachment-shaped growth argument for keeping it off the database file.

A `command` extension point now also carries `permission`: the declared
permission key (from the manifest's own `permissions`) a caller must hold to
reach it. `http::module_commands` checks
`Store::user_has_module_permission` before ever calling the host - the route
is gating, the host is execution, and slim still has no notion of what any
command actually does.

## The code-block-runner extension point

The client's "Run" affordance on a fenced code block is driven by a second
extension-point kind, `code-block-runner`: `{ "kind": "code-block-runner",
"name": "...", "permission": "<permKey>", "command": "<cmd>" }`. `permission`
works exactly as it does for `command`; `command` names one of the
manifest's own `command` extension points, checked at manifest-validation
time the same way `permission` is checked against `permissions`.

`GET /modules/code-block-runners` (any authenticated caller, not
`MANAGE_SERVER`) answers every `(module_id, command)` pair from an installed,
enabled module whose `code-block-runner` permission the caller holds. This
is the entire mechanism: the client offers Run when the list is non-empty
and POSTs to `/modules/{moduleId}/commands/{command}` exactly as
`runModuleCommand` already does. slim has no hardcoded notion of
"code-exec" anywhere in this path - a deployment with no such module
installed gets an empty list and no Run affordance at all, and a module
declaring `code-block-runner` is free to be anything a manifest author
wants to expose on a code block, not only a language sandbox.

A `code-block-runner` also carries an optional `language` (a short slug,
validated the same way a permission key is): which fenced-block language it
matches. Discovery hands it straight through, unvalidated any further,
alongside `module_id` and `command`. This is what lets two runner modules
coexist - v1 offered the first discovery result unconditionally, so a
second installed runner could never be reached. The client, not slim,
normalizes case and resolves a small alias table (`js`/`node` ->
`javascript`, `py` -> `python`, `sh`/`bash` -> `shell`, `md` ->
`markdown`) before comparing a block's own fence tag against a runner's
declared language; a runner with no `language` is a wildcard, matching any
block, which is what keeps a deployment with a single older runner working
unmatched. Several matching runners resolve to whichever discovery listed
first - slim has no notion of which runner is "better" for a language, only
of match or no match.

A bare `command` extension point (no `code-block-runner` alongside it) gets
a UI path too: the Dock's own module view renders a small panel per
`command` an installed and enabled module declares, whose permission the
viewer holds - a text input and Run button against the same
`POST /modules/{moduleId}/commands/{command}` route, rendering the same
`{ok, output}` / `{ok: false, error}` shape the code-block runner already
does. The client has no way to learn client-side whether the viewer holds
an arbitrary module permission without re-deriving the role editor's own
per-role grants, so the panel is shown unconditionally to whoever reaches
the Dock (already `MANAGE_SERVER`-gated) and a caller lacking the module's
own permission simply sees the 403 surface inline, the same as any other
transport failure - never a second, weaker permission model bolted onto the
client to avoid that one round trip.
