# Building a slim module

This is the guide for writing a module that runs on a slim deployment.

A module is a small, sandboxed WebAssembly program.
It receives an input and returns an output, and it can reach nothing else - no network, no filesystem, no host state.
That single constraint is the whole of the v1 security model, and it is what lets a deployment run community-authored code at all.

Read `docs/decisions/0021-modules-and-the-dock.md` for why the system is shaped this way, and `docs/decisions/0022-module-extensibility-and-evolution.md` for how it grows.
This document is the practical how-to; those two are the reasoning.

## What a module can do

A module extends slim through a small set of bounded contracts.
It never patches slim, and slim never learns what any particular module does.
Everything a module offers is declared in its manifest as an *extension point*, and slim only ever routes a request to it and renders whatever comes back.

Today a module can:

- Register a **command** that runs on demand and returns text.
- Offer a **code-block runner** so a fenced code block in chat grows a Run button.
- Offer a **slash command** the composer surfaces as `/name`.
- Offer an **app** a member launches into a channel as a live, shared surface.
- Draw an interactive **scene** (a board, a chart, a small game) as its output, instead of plain text.

A module cannot, yet, post a message on its own, store state between calls on the host, or react to an event.
Those need mediated host capabilities, which are deferred by design - see [Limits and the security model](#limits-and-the-security-model).

## Quickstart

A module is any wasm binary that follows the ABI below.
The examples here are Rust compiled to `wasm32-unknown-unknown`, which is the toolchain the reference modules in [slim-addons](https://github.com/NC1107/slim-addons) use, but nothing in slim requires Rust.

A minimal module that echoes its input back:

```rust
// src/lib.rs
use std::alloc::{alloc as sys_alloc, Layout};

/// The host calls this once to get somewhere to write the request.
#[no_mangle]
pub extern "C" fn alloc(len: i32) -> i32 {
    let layout = Layout::from_size_align(len as usize, 1).unwrap();
    unsafe { sys_alloc(layout) as i32 }
}

/// The host writes the request at `in_ptr`/`in_len`, then calls this.
/// Return a packed `(out_ptr << 32) | out_len` pointing at the response.
#[no_mangle]
pub extern "C" fn run(in_ptr: i32, in_len: i32) -> i64 {
    let request = unsafe {
        std::slice::from_raw_parts(in_ptr as *const u8, in_len as usize)
    };
    // The request is {"command": "...", "input": "..."} as UTF-8 JSON.
    // Echo a success response of the same shape the host expects.
    let response = br#"{"ok":true,"output":"hello from a module"}"#;
    let ptr = response.as_ptr() as i64;
    (ptr << 32) | (response.len() as i64)
}
```

```toml
# Cargo.toml
[package]
name = "echo"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[profile.release]
opt-level = "s"
lto = true
```

Build it:

```bash
cargo build --release --target wasm32-unknown-unknown
# -> target/wasm32-unknown-unknown/release/echo.wasm
```

That wasm plus a manifest (below) is a complete module.
The reference modules parse the request and build the response with `serde_json` rather than by hand; the raw version above is only to show that nothing magic is happening.

There is a ready-to-copy starter in `slim-addons/modules/_template/`, which is the fastest way to begin.

## The module ABI (v1)

A module is a wasm binary that **exports exactly two functions and one memory, and imports nothing at all**.
A single import of any kind is refused at install time rather than sandboxed, because the point of the model is that a module has no ambient authority to sandbox in the first place.

- `memory` - the module's exported linear memory.
- `alloc(len: i32) -> i32` - reserve `len` bytes inside the module's own memory and return a pointer to them.
  The host calls this once, before `run`, to get somewhere to write the request.
- `run(in_ptr: i32, in_len: i32) -> i64` - given the request the host just wrote at `in_ptr`/`in_len`, return a packed `(out_ptr << 32) | out_len` pointing at the response.
  The response may live anywhere the module likes: its own static data, a second `alloc`, or the input region reused in place.

The host writes a UTF-8 JSON request into the region `alloc` returned, calls `run`, and reads `out_len` bytes back at `out_ptr` as a UTF-8 JSON response.
The host only moves bytes; it has no opinion about what is inside them beyond the request/response shapes below.

The ABI is versioned as v1.
A different execution contract would be a new ABI version, not an edit to this one.

## The command protocol

Every extension point that runs is, underneath, a call to one of the module's commands.

The **request** the host writes is a JSON object:

```json
{ "command": "roll", "input": "2d20+3" }
```

- `command` is the name of a `command` extension point the module declared.
- `input` is a string whose meaning is entirely the module's own - a code snippet, a dice notation, a JSON blob, whatever the command wants.

The **response** the module returns is a JSON object, one of two shapes:

```json
{ "ok": true,  "output": "..." }
{ "ok": false, "error": "..." }
```

- On success, `output` is the module's result as a string.
  If that string happens to be a [scene](#the-scene-contract), slim paints it; otherwise it is shown as text.
- On failure, `error` is a human-readable message.
  A failure here is the module's own "I could not do this" (a syntax error in the snippet, say) - not a host refusal.
  Host refusals (not installed, not enabled, no permission, out of fuel) never reach the module and are surfaced separately.

## The manifest

A module is described by a `manifest.json`.
This is what slim validates at install time and persists; it is the contract's source of truth.

```json
{
  "schema": 1,
  "id": "dice",
  "name": "Dice",
  "version": "0.3.0",
  "summary": "Roll dice notation like 2d20+3.",
  "description": "A longer explanation shown on the module's Dock page.",
  "author": "you",
  "homepage": "https://github.com/you/your-addons",
  "runtime": {
    "backend": "wasm",
    "limits": { "memory_mb": 64, "wall_ms": 2000, "fuel": 200000000 }
  },
  "artifact": {
    "kind": "wasm",
    "path": "modules/dice/0.3.0/module.wasm",
    "sha256": "<64 hex chars>"
  },
  "permissions": [
    { "key": "roll", "name": "Roll dice", "description": "Roll dice in this space." }
  ],
  "capabilities": ["command.register"],
  "extension_points": [
    { "kind": "command", "name": "roll", "permission": "roll", "description": "Roll dice." },
    { "kind": "slash-command", "name": "roll", "permission": "roll", "command": "roll", "description": "Roll dice like 2d20+3." }
  ]
}
```

Field by field:

- `schema` - the manifest envelope version, currently `1`.
  A version slim does not recognise is rejected cleanly.
- `id` - a safe slug (lowercase letters, digits, hyphens), unique in a registry, and stable across versions.
  It is also the natural `/id` keyword for an [app](#app) launch.
- `name`, `summary`, `description`, `author`, `homepage` - shown on the module's Dock page. `name` and `summary` are required.
- `version` - a version string; bumping it is how an upgrade is offered (see [Publishing](#publishing-a-module)).
- `runtime.backend` is `"wasm"`. `runtime.limits` is optional and each field within it is optional; see [Limits](#limits-and-the-security-model).
- `artifact.path` is the wasm's path within the registry, and `artifact.sha256` is its SHA-256, which slim pins - a mismatch refuses to run.
- `permissions` are the permission keys this module introduces.
  A deployment's admins grant these to roles; nobody, not even an administrator, holds a module's permission implicitly.
- `capabilities` are strings a module declares it wants.
  They are stored on install but not yet enforced (see [Limits](#limits-and-the-security-model)); declare only what you actually intend to use.
- `extension_points` are what the module offers, covered next.

## Extension-point kinds

Each extension point has a `kind`, a `name`, and an optional `description`.
Every kind slim knows gates on a declared `permission`; the runner-like kinds also name the `command` they invoke.
A kind slim does **not** recognise is accepted and stored, then ignored - so a client that learns a future kind can use it while older servers simply carry it, and a module can target the future without waiting for every deployment.

### command

Runs on demand and returns text (or a scene).

```json
{ "kind": "command", "name": "roll", "permission": "roll", "description": "Roll dice." }
```

- `permission` (required) names one of this manifest's own `permissions[].key`.
- `name` is the command name the request's `command` field carries.

A bare `command` is not, by itself, visible anywhere in the UI - it is the thing the runner-like kinds below invoke.
A module that only wants a command reachable through the Dock's own run panel needs just this.

### code-block-runner

Grows a Run button on a fenced code block in chat.

```json
{ "kind": "code-block-runner", "name": "Run in chat", "permission": "run", "command": "run", "language": "javascript" }
```

- `command` (required) names a `command` extension point this manifest also declares.
- `language` (optional) is the fence tag this runner matches (`js`, `python`, ...).
  Omit it for a wildcard that matches any block.
  The client normalises case and applies a small alias map (`js` -> `javascript`) before comparing.

When a member runs a block, the result is stored against the message and broadcast, so everyone viewing sees the same output without rerunning it.

### slash-command

Offered in the composer as `/name`.

```json
{ "kind": "slash-command", "name": "roll", "permission": "roll", "command": "roll", "description": "Roll dice like 2d20+3." }
```

- `name` is the keyword the composer offers as `/name`; a member types `/roll 2d20+3`.
- Everything after the keyword is handed to the command as its `input`.

### app

Launched into a channel as a message that renders as the module's own interactive surface, shared across everyone viewing it.

```json
{ "kind": "app", "name": "Game of Life", "permission": "play", "command": "life", "description": "Launch a live board in the channel." }
```

- `name` is what the composer's apps menu shows.
- The launch also has a `/id` alias (the module's `id`), so `/game-of-life` launches it.
- A launch runs the command once with an empty `input`, so a well-behaved app returns its initial frame for empty input.
  From then on the surface is driven entirely by the [interactive scene](#interactive-scenes) protocol, shared through the same stored-and-broadcast mechanism a code-block runner uses.

## The scene contract

A command normally returns text.
If instead it returns a string that is a JSON object tagged `"$slim": "scene/1"`, slim paints it as a scene.
This is a client-side reading of an ordinary output string - there is no separate wire type and nothing to declare.
A module opts in simply by choosing to emit one, and any output that is not a valid scene falls back to plain text.

```json
{
  "$slim": "scene/1",
  "width": 100,
  "height": 100,
  "background": "surface",
  "ops": [
    { "op": "rect", "x": 10, "y": 10, "w": 80, "h": 30, "fill": "accent", "r": 6 },
    { "op": "text", "x": 50, "y": 25, "s": "hello", "fill": "text", "align": "center", "size": 8 }
  ],
  "status": "a caption under the scene",
  "controls": [],
  "live": false
}
```

- `width` and `height` are the scene's own logical units; the painter scales them to whatever box it is given.
  Coordinates in ops are in these units.
- `background` is an optional fill for the whole scene.
- `status` is an optional one-line caption shown under the scene.
- `ops` is the list of drawing primitives, painted in order (first is bottom).

### Colours

A colour is either a literal `#rrggbb` or the name of a theme token, which the painter resolves against the viewer's theme so a scene looks native in light and dark alike:

`accent`, `surface`, `sunken`, `muted`, `text`, `border`, `danger`.

Prefer tokens; a module that hard-codes hex will look wrong in one theme or the other.

### Ops

| op | fields |
| --- | --- |
| `cells` | `cols`, `rows`, `data` (one char per cell, row-major, each a palette index `'0'`..), `palette` (list of colours), `gap`, `tap` |
| `rect` | `x`, `y`, `w`, `h`, `fill`, `stroke`, `sw` (stroke width), `r` (corner radius), `tap` |
| `circle` | `cx`, `cy`, `r`, `fill`, `stroke`, `sw`, `tap` |
| `line` | `x1`, `y1`, `x2`, `y2`, `stroke`, `sw` |
| `text` | `x`, `y`, `s` (the string), `fill`, `size`, `align` (`left`/`center`/`right`) |

`cells` is the workhorse for boards, heatmaps, and automata: a grid of palette indices drawn in one op.
An op slim does not recognise is skipped rather than failing the scene, so a new op is an additive change a newer client can use.

## Interactive scenes

A scene becomes interactive by offering `controls` and carrying `state`, and by drawing ops with a `tap`.

```json
{
  "$slim": "scene/1",
  "width": 3, "height": 3,
  "ops": [
    { "op": "cells", "cols": 3, "rows": 3, "data": "000010000", "palette": ["sunken", "accent"], "tap": "toggle" }
  ],
  "controls": ["step", "clear"],
  "state": "<opaque string the module hands itself back>",
  "live": true
}
```

- `controls` is a list of button labels shown under the scene.
- `state` is an opaque string slim stores and hands back on the next call - it is how a stateless module remembers the board between frames.
  Put whatever you need in it (packed cells, a generation counter, a seed); slim never looks inside.
- An op's `tap` makes it interactive.
  A `cells` op with `tap: "toggle"` reports a tapped cell as the action `"toggle:row,col"`.
  A `rect` or `circle` with `tap: "spin"` reports the bare action `"spin"`.
- `live` tells the client the scene can still change; a control press or tap while `live` re-invokes the module.

When a member presses a control or taps, slim calls the module's command again, with the `input` being a JSON object:

```json
{ "action": "step", "state": "<the state from the last scene>" }
```

The module reads `action` and `state`, computes the next frame, and returns a new scene (with a new `state`).
Return a scene with `live: false` to stop, or a non-scene/error to end with a message.
Because the frame is stored and broadcast, every viewer of the message sees the same evolving surface, and a long step runs once for everyone.

The Game of Life reference module (`slim-addons/modules/game-of-life`) is the worked example of this whole loop.

## Limits and the security model

A module is pure compute with zero host imports.
It receives an input and returns an output and can reach nothing else - not the network, not the filesystem, not other modules, not slim's own state.
This is deliberate and is the entire v1 security model.

Every `run` call is held to resource limits, taken from the manifest's `runtime.limits` or these defaults when unset:

| limit | default | meaning |
| --- | --- | --- |
| `memory_mb` | 16 | linear-memory ceiling for the call |
| `wall_ms` | 1000 | wall-clock deadline; a command is a synchronous request-response, not a background job |
| `fuel` | 50,000,000 | roughly one unit per executed instruction, so this bounds a runaway loop |

Set them higher in the manifest if your module genuinely needs it (Game of Life uses 64 MB / 2 s), but a shared row that rides fan-out is capped well below whatever a module can produce, so enormous output is truncated regardless.

`capabilities` a module declares (`message.post`, `kv.store`, ...) are stored on install but **not yet enforced or granted**.
The classes that need them - a module that posts a message, stores state on the host, or reacts to an event - need *mediated host capabilities*, a future phase that adds specific, capability-gated host functions rather than ambient access.
The manifest slots for this exist now so a module can declare its intent; the enforcement and the host functions are deferred.
Do not rely on a capability doing anything today.

## Publishing a module

Modules are served from a registry: a static site (or repo) with an index and one directory per module.
The reference registry is [slim-addons](https://github.com/NC1107/slim-addons), and its layout is the contract:

```text
index.json                         # the catalogue
modules/<id>/manifest.json         # the module's manifest (latest version)
modules/<id>/<version>/module.wasm # the pinned artifact for each version
```

`index.json` lists every module with just enough to browse:

```json
{
  "schema": 1,
  "modules": [
    { "id": "dice", "name": "Dice", "version": "0.3.0", "summary": "Roll dice notation like 2d20+3." }
  ]
}
```

To publish or update a module:

1. Build the wasm and put it at `modules/<id>/<version>/module.wasm`.
2. Compute its SHA-256 and set `artifact.sha256` and `artifact.path` in the manifest.
3. Bump `version` in both `manifest.json` and `index.json`.
4. Serve the registry over HTTPS and point a deployment's Dock at it.

A deployment installs a module by version, and slim records the manifest's extension points **at install time**.
That means changing a manifest in place does not change an installed module - a deployment must upgrade to the new version to pick up new extension points or permissions.
Bumping the version is therefore the deliberate act that offers an upgrade, even when the wasm itself is unchanged.

An installed module never runs a wasm whose SHA-256 does not match its manifest, so re-hosting a tampered artifact under the same version cannot take effect.

## Testing a module

Because a module is a pure `{command, input} -> {ok, output}` function, most of it can be tested as ordinary code in whatever language you wrote it in, before any wasm is involved.
The reference modules keep their logic (parsing, the automaton, the scene builder) in plain functions with unit tests, and keep the ABI `run`/`alloc` shim thin.

To test the whole thing end to end, install the built wasm on a dev deployment, grant yourself its permission, and exercise it from chat.
A scene is easiest to iterate on this way, since the interactive loop only exists once the client is painting it.

## Forward compatibility

The contracts here are versioned, and each grows additively (see decision 0022):

- An unknown extension-point kind, an unknown capability, and an unknown scene op are all accepted and ignored rather than rejected, so a module can target a newer client on an older server.
- The manifest envelope (`schema`) and the ABI (`v1`) are the two things a breaking change would bump; everything else grows within them.

Build against the contract, not against a particular client's current rendering, and your module keeps working as slim grows.
