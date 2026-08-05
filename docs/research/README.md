# Research corpus index

48 files, roughly 11,000 lines, spanning 2026-07-23 to 2026-07-30.

**Status: this is a point-in-time record, not a description of current state.**
Most of it (everything dated 2026-07-23) was written before a line of implementation code existed, to decide what to build and then to attack that decision before committing to it.
Where any file here disagrees with the running code or with `docs/decisions/`, the code and the decision records win.
Nothing in the 2026-07-23 set should be read as a claim about what slim-m does today; read `CLAUDE.md` for that, and use this corpus for why a choice was made, not for whether it still holds.

Two adversarial-review conventions recur through every dated set below and are worth knowing before reading any one file: a review reserves "critical" for a finding that would force a redesign before implementation starts, and later reviews (the two audits) split into a second pass whose only job is trying to refute the first pass's own findings, so a rejected-findings file sits beside each one.

## Pre-build domain research and its paired adversarial reviews (2026-07-23)

Each specialist report below fed `STRATEGY.md`; most have a sibling `*-review.md` that red-teamed it before anything was built from it. Superseded, where marked, by the decision or feature that was actually shipped.

| Report | Review | Covers | Status |
| --- | --- | --- | --- |
| [appstore.md](appstore.md) | [appstore-review.md](appstore-review.md) | App Store and Play Store compliance: the invite-code account model, Sign in with Apple, account deletion, screen share and recording permissions, voice background modes | Not superseded; still the fullest written compliance analysis. Re-check guideline dates against Apple's and Google's current policies before relying on a specific clause - both cite dates current as of January and April 2026 |
| [audio.md](audio.md) | [audio-review.md](audio-review.md) | The seven-sound notification family, the Python synthesis pipeline, loudness normalization, per-OS playback | Partly superseded: the synthesis pipeline shipped as designed (`assets/audio/`, `synth.py`), but per-platform playback has not, and the normalization approach changed from the plan for a reason `synth.py` documents. See `docs/ROADMAP.md` Phase 8 |
| [database.md](database.md) | [database-review.md](database-review.md) | Schema for users, RBAC, channels, messages, attachments, invites, canvas objects; indexing, pagination, FTS5, migrations, retention | Superseded by the schema actually shipped (21 migrations under `crates/slimm-server/migrations/`) and by `docs/decisions/0002-architecture-followups.md`; read for the reasoning behind the shape, not for the current schema |
| [devops.md](devops.md) | [devops-review.md](devops-review.md) | Repo topology, CI/CD pipeline structure, versioning, GHCR publishing, Dockerfile and compose, Linux and iOS release paths | Superseded by the CI actually running; see `docs/ci.md` for what the workflows do today |
| [flutter-client.md](flutter-client.md) | [flutter-client-review.md](flutter-client-review.md) | Flutter package and module structure, targeting iOS and Linux first | Superseded by the client as built (`client/packages/`); the design-system and UI-alignment work in `CLAUDE.md` postdates this by a full visual identity pass |
| [media.md](media.md) | (none) | Voice, video and screen share: self-hosted LiveKit as the SFU, kept separate from chat and canvas control plane | The SFU decision stands and shipped; specifics superseded by the Phase 4 voice work `CLAUDE.md` documents |
| [networking-relay.md](networking-relay.md) | [networking-relay-review.md](networking-relay-review.md) | Push relay registration, APNs and FCM, payload privacy, iOS background execution, delivery volume | Superseded by the relay as built and deployed (`slim-m-relay`); see `CLAUDE.md`'s Phase 3 sections |
| [oss.md](oss.md) | [oss-review.md](oss-review.md) | Repository layout, per-component licensing, contribution workflow, governance | Mostly still accurate as repo layout; contribution conventions in `CLAUDE.md` are the current source |
| [performance.md](performance.md) | [performance-review.md](performance-review.md) | Client and server performance budgets, benchmark infrastructure, CI regression gates | Superseded in specifics by `perf/baselines/` and the measured numbers in `CLAUDE.md`; the budget-setting approach still holds |
| [realtime-sync.md](realtime-sync.md) | [realtime-sync-review.md](realtime-sync-review.md) | WebSocket gateway lifecycle, event ordering, offline catch-up sync, read state, typing and presence, push trigger hook | Superseded by the shipped protocol (Phase 1 PRs #13-#14); the per-scope sequence design described here is what shipped |
| [security.md](security.md) | [security-review.md](security-review.md) | Trust boundaries, threat model, transport-only encryption in v1, pre-wired E2EE keys | The v1 decisions still hold (`docs/decisions/0001`); read for rationale, not for what has since been found and fixed (see the two later audits below) |
| [ux.md](ux.md) | (none) | Navigation, responsive behavior, command palette, onboarding, entering voice and the canvas, accessibility | Substantially superseded by `docs/design/design-language.md` and `docs/decisions/0004-visual-identity-review.md`; where the two disagree on a specific number (touch target, font scale), decision 0004 is the tiebreaker, and `docs/design/design-language-review.md` flags exactly where they diverged |
| [voice-canvas.md](voice-canvas.md) | [voice-canvas-review.md](voice-canvas-review.md) | The Voice Canvas design: per-object model, coordinate handling, sourced from the echo-messenger reference notes | Superseded by the Phase 5 spikes below and by the shipped first slice (`CLAUDE.md`, "The canvas, first visible slice"); its own inline note already records the `window` content-kind contradiction as settled by decision 0004 |

## The stack decision (2026-07-23)

Three competing proposals for the foundational server stack, each written to a different lens, and the decision that weighed them.

| Document | Covers | Status |
| --- | --- | --- |
| [stack-proposal-lean.md](stack-proposal-lean.md) | The server stack optimized for self-host footprint | Superseded by [stack-decision.md](stack-decision.md), which did not choose this lens outright |
| [stack-proposal-maintainable.md](stack-proposal-maintainable.md) | The server stack optimized for contributor pool and long-term maintainability | Superseded by the decision, which drew heavily on this lens |
| [stack-proposal-safe.md](stack-proposal-safe.md) | The server stack optimized for correctness and type safety | Superseded by the decision |
| [stack-decision.md](stack-decision.md) | Accepted for implementation, 2026-07-23: Rust, Axum, Tokio, embedded SQLite via sqlx, UUIDv7 plus per-scope sequence | Not superseded; this is the foundational decision the whole server is built on, and it held |

## Stack validation: due diligence on the decided stack (2026-07-23)

A library and tooling due-diligence pass against the already-decided stack, one report per region plus a compiled verdict. `SUMMARY.md` is the only file in this whole corpus with a live inbound link from outside `docs/research/`: `docs/decisions/0003-library-decisions.md` cites it directly.

| Document | Covers | Status |
| --- | --- | --- |
| [SUMMARY.md](stack-validation/SUMMARY.md) | Compiled verdict across all seven regions below | Cited by `docs/decisions/0003-library-decisions.md`, which also records one correction to it (a Linux-media finding) |
| [data-sqlite.md](stack-validation/data-sqlite.md) | SQLite WAL layer, connection pooling, migration tooling, backup, write-throughput ceilings | A 2026-07-23 snapshot of library maturity and status; not re-validated since |
| [devops-packaging-relay.md](stack-validation/devops-packaging-relay.md) | Cross-compilation, base images, SBOM tooling, the Go relay's router library | Snapshot, not re-validated since |
| [flutter-client.md](stack-validation/flutter-client.md) | The Flutter client package set: maintenance, licensing, platform gotchas | Snapshot, not re-validated since |
| [media-canvas.md](stack-validation/media-canvas.md) | Media streaming, WebRTC, and canvas rendering library choices | Snapshot, not re-validated since; see the Phase 5 spikes for measured canvas behavior instead of library-maturity opinion |
| [rust-server-core.md](stack-validation/rust-server-core.md) | The Rust web and runtime layer | Snapshot, not re-validated since |
| [security-crypto-push.md](stack-validation/security-crypto-push.md) | Security, crypto and push-payload encryption libraries | Snapshot; flagged three gaps at the time (push-payload encryption unspecified, UUIDv7 unsuitable for security tokens, Argon2id concurrency bounding needed) that the shipped auth design (Phase 1 PR #10) addresses |
| [wire-protocol-codegen.md](stack-validation/wire-protocol-codegen.md) | The schema-first wire protocol and code-generation toolchain | Superseded: the codegen approach it validates was never built. See `schema/README.md`'s corrected header - the wire protocol is schema-documented, not schema-generated |

## Reference studies of the two prior projects

Notes on the two existing codebases slim-m draws on or explicitly avoids repeating. Not superseded; these are historical reference material rather than claims about slim-m itself.

| Document | Covers |
| --- | --- |
| [reference-check-in-relay.md](reference-check-in-relay.md) | check-in-relay (Go), the project the slim-m push relay is adapted from, and the scoped-key problem it solves |
| [reference-echo-messenger.md](reference-echo-messenger.md) | echo-messenger (`decentralized-chat-app`), the prior project whose Voice Canvas (voice-lounge) slim-m's own canvas draws on and deliberately does not repeat the mistakes of |

## Later dated work

Everything below postdates the pre-build research above by weeks and reports on the system as it was actually measured or reviewed while running. Each is still current as reference material for the area it covers, though later entries in `CLAUDE.md` record what has been fixed since any individual finding.

| Document | Date | Covers |
| --- | --- | --- |
| [canvas-spike-server.md](canvas-spike-server.md) | 2026-07-26 | Phase 5 spike, server half: the R-Tree viewport query, measured against the stated soft caps |
| [canvas-spike-client.md](canvas-spike-client.md) | 2026-07-26 | Phase 5 spike, client half: uniform-grid viewport culling and the off-Riverpod render path |
| [nine-specialist-audit-2026-07-29.md](nine-specialist-audit-2026-07-29.md) | 2026-07-29 | Nine parallel specialist reviews (five code, four screenshot) over the running product; consolidated findings, fixes, and deliberate deferrals |
| [audit-2026-07-30/](audit-2026-07-30/README.md) | 2026-07-30 | Thirty-three specialist reviews over the whole stack (screens, client code, server code, security, process) plus the rejected-findings list; see that directory's own README for current status, which this cleanup pass rebuilt from merged-PR evidence |
| [canvas-removal-design-2026-07-31.md](canvas-removal-design-2026-07-31.md) | 2026-07-31 | The design for canvas slice two (erase, clear, undo, restore, and the `canvas_ops` stream): three independent designs, three adversarial judges, and the synthesised implementation plan the PRs are built from. Live rather than historical while those PRs are open |
| [background-blur-spike.md](background-blur-spike.md) | 2026-08-01 | Camera background blur/replacement spike, ahead of the camera-publish work: whether `livekit_client`/`flutter_webrtc` have a frame-transform seam, what segmentation model options cover which platforms, and the frame-budget evidence behind the recommendation to ship it as a reduced, per-platform feature rather than uniformly. Cited directly from every file in [docs/os_backlog/](../os_backlog/README.md), which is the per-platform summary of this and every other known platform gap |
| [review-product-2026-08-02.md](review-product-2026-08-02.md) | 2026-08-02 | A rendered product and UX review: every routed screen actually opened and looked at, not read from source. A real illegible-text bug in Space Settings, the voice join screen's empty space, the canvas's gap against its own "signature feature" billing, and a first-run walkthrough from a fresh bootstrap |

## Why this corpus stays, unpruned

Thirteen files above have no inbound reference from anywhere outside `docs/research/` itself (the eight `*-review.md` siblings with no cross-citation, and five of the seven `stack-validation/` reports). None of them are deleted: each records how the architecture was decided or the adversarial review that tested a decision before it was built, and that is exactly the kind of record this project has separately learned is expensive to lose (see `docs/decisions/`'s own citations back into this directory). Being unreferenced is not the same as being wrong; several of the individually-cited files above (`SUMMARY.md`, `flutter-client.md`, `voice-canvas.md`) are reachable only through one or two links, which is a thin trail rather than an argument for removal.
