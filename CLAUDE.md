# slim-m knowledge base

Development context and project state for slim-m.
This is the durable memory of the project: read it first when picking the work back up.
Kept concise on purpose; the deep detail lives in `docs/`.

## What this is

slim-m is a lightweight, self-hostable, Discord-style messaging platform (text, voice, screen share) with an infinite collaborative Voice Canvas as its signature feature.
Flutter client, Rust server, and a separate Go push relay.
The name "slim-m" is a working placeholder; a final name is chosen before 1.0.

Core reading, in order: [docs/BRIEF.md](docs/BRIEF.md), [docs/STRATEGY.md](docs/STRATEGY.md), [docs/ROADMAP.md](docs/ROADMAP.md), and the decision records in [docs/decisions/](docs/decisions/).

## Current state (2026-07-25)

Phases 0 (foundations), 1 (server and protocol core), and 2 (client shell and text messaging) are complete.
Phase 3 (push relay and notifications) is complete on every exit criterion except the two that need hardware or a Mac; see "Still open in Phase 3" below.

Repositories (public, owner NC1107):
- Core monorepo: https://github.com/NC1107/slim-m (Rust server + Flutter client + shared schema).
- Push relay: https://github.com/NC1107/slim-m-relay (Go, adapted from check-in-relay). Local checkout at `../slim-m-relay`.

Server 0.8.0 is released (2026-07-26) with signed multi-arch GHCR images and native musl binaries; the live instance tracks `latest` and auto-updates.

### The phase 3 audit (2026-07-25), and what it changed

A nine-dimension review of the whole backbone, with every finding put through an adversarial refutation pass.
It confirmed Phase 3 itself: the sealed-box envelope is content-free and domain-separated, per-device push keys are a dedicated keypair, the relay logs only counts and a key id (never a token or payload), the LAN-only disable path works, and the cross-repo contract test drives a server-generated fixture through the relay's real router.

What it found was mostly Phase 2 debris, and one live hole.
**Registration was never gated on an invite.**
The `TODO(phase 2)` asking for the gate was written before the invite flow existed, the invite flow shipped in phase 2, and the gate did not, so from the moment a deployment was claimed anyone who knew its address could create an account and inherit `@everyone`'s view and send rights.
This was reproduced against the live instance, not inferred: an anonymous caller registered, listed both channels, and read real messages (probe account deleted afterwards).
`register_account` now applies the join policy in the same transaction as the account insert, and the client sends the code with the signup rather than redeeming after it.

Everything else fixed in the same pass, all with tests that fail without the fix:

- Report resolution checked only deployment-wide MANAGE_MESSAGES while listing re-checks it per channel, so a moderator denied it in one channel could not read its reports but could still dismiss them.
- `PATCH .../messages/{id}` charged no rate limit while send and delete both did.
- An idempotent send retry re-fanned-out and re-pushed, outside the debounce window that exists to stop exactly that.
- Three transactions read before writing under a deferred `BEGIN`. SQLite refuses to promote a read snapshot to a writer and returns SQLITE_BUSY immediately, ignoring `busy_timeout`; 24 concurrent sends to one channel failed with "database is locked". They use `Store::begin_write` (`BEGIN IMMEDIATE`) now.
- The client's local database is one file for the whole app and nothing ever cleared it, so the channel list and message text of the account signing out were read straight back by whoever signed in next on that device.
- `docker-compose.yml` fell back to `changeme_api_key` and a matching secret for LiveKit, character for character the placeholders in `.env.example`, and still pinned the very first server release. Both variables now use the `:?` form so compose refuses to start and names the missing one.
- Four workflows ran actions on mutable tags behind a "pin to commit SHA before public" comment in a repo that has always been public.
- Nothing built with `--locked`, so the committed lockfile was advisory and had been recording 0.6.0 while Cargo.toml said 0.8.0.
- No index on `sessions.device_id`, which push fan-out and every device revocation path filter by; and nothing ever deleted expired access tokens, refresh tokens, or connect tickets.
- The FTS5 delete and update triggers issued their `'delete'` unconditionally while the insert trigger is guarded on `is_encrypted`, which corrupts an external-content index. Dormant until E2EE lands, fixed while the table still holds no encrypted rows.
- `/sync` returned messages with an empty `reactions` array while list and search filled it in.
- `schema/openapi.yaml` claimed types were generated from it and CI failed on drift; `models.dart` claimed a contract test asserting every model matches a schema entry. Neither existed. Both headers now state what CI actually gates (method and path, additive-only, valid OpenAPI) and what it does not (bodies, on any of the three sides).
- Push fan-out evaluated permissions for every live user on every message before the debounce was consulted; it starts from who has a usable push registration now.

Measured for the first time, closing the Phase 1 exit criterion that had never been taken: idle RSS of the release binary is 7,296 kB steady and 25,760 kB peak, inside the under-30MB budget.
`perf/baselines/0.8.0.json` is the first committed baseline after eight releases without one.
Note it was taken on glibc while releases ship musl, whose allocator fragments differently under Tokio.

Phase 1 merged so far:
- Core SQLite schema (PR #3): users, auth tables, RBAC, channels, per-scope sequence counters, messages, reactions, attachments, invites, read state, canvas tables, FTS5.
- Identity and message store (PR #8): UUIDv7 newtype ids and a distinct per-scope `Seq`; a `Store` with atomic per-(channel, stream) sequence allocation and idempotent-by-message-id send; edit (FTS re-indexed by trigger); keyset pagination; integration tests for the ordering and idempotency invariants.
- Auth (PR #10): Argon2id (OWASP 19 MiB, semaphore-bounded with a fail-fast acquire timeout), opaque server-side tokens (256-bit secrets stored as SHA-256), short access tokens, device-bound refresh rotation with reuse detection and a grace window, single-use WS connect tickets, instant revocation. Migration 0003 (access_tokens, ws_tickets). Rotation and ticket redemption use an atomic claim-first UPDATE so concurrent races serialize cleanly.
- Permission evaluator (PR #11): a 63-bit `Permissions` bitmask and a pure `evaluate()`: @everyone base, role union, ADMINISTRATOR bypass, then channel overwrites (@everyone, role tier deny-wins, member overwrite absolute). Store loading (create_role/assign_role/set_*_overwrite, permissions_in_channel/base_permissions/has_permission). Migration 0004 enforces a single @everyone role.
- Message endpoints (PR #12): authenticated + authorized REST send/list/edit (`POST`/`GET /channels/{id}/messages`, `PATCH .../{message_id}`), wiring the evaluator (view to read, view+send to post, authorship-or-manage to edit). Shared http `error`/`extract` modules. Send idempotency scoped to (channel, author) so a reused id cannot leak a foreign message.

- WebSocket envelope and fan-out (PR #13): `/ws` authenticated by a redeemed connect ticket in a hello frame with protocol negotiation, a typed JSON envelope, a broadcast hub with per-event authorization, backpressure close, a bounded write timeout, a connection cap, 4 KiB frame limits, and logout closing live sockets.
- Read state and bundled sync (PR #14): monotonic last-read seq with derived unread, and `POST /sync` taking per-scope cursors with per-scope, aggregate, and snapshot-gap caps. A nonexistent channel now grants no permissions, so channel existence is not observable.
- Account deletion (PR #15): purge personal data, anonymize authored content, tombstone and free the username, revoke sessions and close sockets, with the login-versus-delete race closed by a write-locked liveness check in `open_session`.

- First-run bootstrap and channel routes (PR #16): the first account to register claims the deployment, seeding @everyone, an admin role, and a general channel, plus GET/POST /channels. Found by deploying and discovering a fresh server could authenticate but not message.
- In-process rate limiting (PR #19): token buckets per (class, key) with sweeping and a hard ceiling, keyed by user when authenticated and peer address otherwise, over-budget callers get 429.

**Phase 1 is complete**, including the rate-limiting deliverable. Server 0.5.0 is released and deployed.

**Phase 2 (client shell and text messaging) is merged.** What landed, in order:
- Wire protocol documented and the Dart API client (PR #21). The schema had drifted to 2 of 15 endpoints; it now documents the real surface.
- Local store (PR #22): Drift, idempotent by message id and order-safe by seq, so live push and catch-up can interleave.
- App shell (PR #23): width-driven adaptive layout, sync that catches up before attaching the socket, optimistic sends.
- Devices, blocking, report intake (PR #24) and invites (PR #27) on the server.
- Settings, safety UI, GoRouter, true-black theme, golden matrix (PR #26).
- Onboarding with the three entry points, invite redemption, unread badges (PR #28).
- Key-storage seam, remappable shortcuts, permessage-deflate interop (PR #29).

**Phase 3 (push relay and notifications) is largely done, and proven on real hardware.**
A backgrounded iPhone running the TestFlight build received a content-free push on 2026-07-25, with the relay logging `delivered=1`.

What landed:
- Server push path (PR #30): device registration scoped to the caller's own session, a client-reported lifecycle signal, a sealed content-free envelope (X25519, carrying only version, kind, channel, message id and seq), and a relay client.
  `PushSender` is a two-state thing rather than an error path, since a LAN-only self-host has nowhere for a relay to reach it.
  Triggering reads the lifecycle report, never raw WebSocket presence, because iOS suspends a socket without closing it.
- Relay hardening (relay PR #1): dead-token pruning, a VoIP topic for calls, a bounded worker pool under a real deadline, a registration ceiling, and `SECURITY.md`/`CODEOWNERS`/`MAINTAINERS.md`.
- Visible alerts (relay PR #2): message and mention kinds send a fixed generic string rather than a silent `content-available` push, which displayed nothing at all without a Notification Service Extension.
- iOS client registration (PR #31) and session persistence (PR #32).
- Android push, sender names, and the cross-repo envelope contract test (PR #33, relay PR #3). The contract job checks out both repos and drives a server-generated fixture through the relay's real HTTP handler.
- The endpoints the frontend still needs (PR #36): 21 routes (message delete, FTS search, profiles and member list, self profile, channel rename/delete, roles, overwrites, admin password recovery, report triage), the openapi contract gate (`tests/openapi_contract.rs`), and three privilege fixes found by adversarial review.
- Android delivery (PR #38): upload keystore signing (verified signer in CI, never debug), a release job attaching apk + aab, and the Play Console app (see identifiers below). First AAB 0.1.0 (4) is on the internal testing track; no testers added yet by owner choice.
- Push reachability in onboarding (PR #39): `/version` reports `push_enabled`, and the sign-in screen (where all onboarding paths land) probes it and shows a non-blocking notice when a server explicitly cannot push. Also fixed the sign-in field hardcoding a LAN address over the onboarding choice.

Still open in Phase 3:
- The iOS Notification Service Extension, which is what would replace "New message" with the decrypted content. It needs a new Xcode target, which cannot be created or tested on this machine.
- The Android half of the exit criterion: a real backgrounded Android device receiving a content-free wake. No Android hardware has been available; the pipeline, registration path, and contract test are done.

Known residuals, deliberately shipped:
- The session write lands just after the in-memory token becomes authoritative, so a process death in that window replays a spent refresh token into reuse detection and forces a sign-out. Recoverable, but closing it means reordering `SlimmApi`'s refresh path.
- The delete-account error path reports its failure but still strands the user.
- Malformed query strings and JSON bodies still return axum's default error rather than the uniform JSON error contract.
- `revoke_device` does not itself publish `SessionRevoked`; the logout and deletion paths do, and both are now covered by socket-closes tests.
- `packaging/flatpak/*.yaml` and `packaging/rpm/*.spec` still do not exist, so a tagged release warns and skips both Linux artifacts. Phase 0's exit criterion names them and Phase 9 owns them properly. Deliberately not guessed at here: an untested manifest that merely looks right is worse than an honest skip, because it produces a broken artifact instead of a visible gap.

## Push credentials and identifiers

Bundle id `top.npcserver.slimm` on both platforms, following the existing `top.npcserver.checkin` convention.
A hyphenated form is legal on iOS but not in an Android `applicationId`, which is why the obvious `top.npc-server.slimm` was rejected.
The bundle id is deliberately not tied to the product name: the App Store display name is a separate field and stays free to change.

- Apple team `76S78SUWVM`, APNs key `AY9T3ZH9JX` (team scoped, sandbox and production; both settings are fixed at creation).
- App Store Connect app id `6794496135`, distribution certificate expiring 2027-07-25, profile `slim-m App Store Distribution`.
- Firebase project `slim-m` on the free Spark plan, FCM v1 enabled. Analytics and Gemini were declined at creation: neither is needed to send a push and both widen what Google sees of a messaging product.
- Play Console: app "slim-m", package `top.npcserver.slimm`, app id `4975488981113040762`, under the "Echo Messenger" developer account (`8924129173175438446`). Play App Signing is on; our keystore is the upload key only.
- Android upload keystore: `~/.secrets/slim-m/android-upload-keystore.jks` (alias `upload`, password alongside in `android-upload-keystore-password.txt`). GitHub secrets `ANDROID_UPLOAD_KEYSTORE_B64`, `ANDROID_KEY_PROPERTIES`, `ANDROID_GOOGLE_SERVICES_JSON` feed the release job.
- Secrets live in `~/.secrets/slim-m/`, mode 600, outside the repo. GitHub secrets are set for the TestFlight and Android pipelines.
- `google-services.json` and `GoogleService-Info.plist` are gitignored on purpose. Google does not class them as secrets, but this repo is public and they carry an API key, so CI injects them like the signing assets. A contributor needs their own to build the mobile targets.

Both store pipelines work from a `client-v*` tag: a signed iOS build reaches the Internal Testers group on TestFlight (automatic distribution on), and a signed apk + aab land on the GitHub release.
The aab still goes to Play by hand (no upload API wired); the first one was uploaded 2026-07-25.
The iOS job needs `set-key-partition-list`, without which `codesign` hangs a headless runner waiting for permission.
Uploading a new Play build: Test and release > Internal testing > Create new release.
The build number is **no longer taken from pubspec**: both store builds pass `--build-number=${{ github.run_number }}`, so it is monotonic and cannot be reused.
That was not cosmetic. `pubspec` sat at `0.1.0+4` through four client tags, so every TestFlight upload after the first carried a build number App Store Connect had already seen.
altool uploads a duplicate happily and the rejection arrives later by email, so all four release runs went green while the iPhone never saw a new build.
The pubspec `+N` is now only a local-build default and does not need touching per release.

Known gaps left from Phase 2, deliberately, and worth picking up before Phase 3 leans on them:
- **The UI has been driven by a human only lightly.** The live instance holds real messages from the owner, so the primary flow has been exercised, but there is no record of a full sign-up-to-send pass written down.
- **Golden images are not committed.** The matrix asserts no overflow at any scale (machine-independent, runs everywhere); the pixel comparison is behind `SLIMM_GOLDENS` with no reference images, because images generated off-CI would never match the runner and would mean a permanently red build. Generate them once on the CI runner and enable the flag there.
- Reactions UI, the shared context menu, the quick switcher, haptics, and history pagination are not built. The server side of reactions exists (PUT/DELETE on `/messages/{id}/reactions/{emoji}`, summaries on list, a ReactionsChanged event).
- The shortcut table exists but is not yet bound into the widget tree.

Open follow-ups noted during reviews: malformed query/JSON bodies still return axum's default error rather than the uniform JSON error contract (low); `revoke_device` does not itself publish `SessionRevoked` (the logout and deletion paths do).

## Running deployment (LAN test instance)

The push relay also runs on this host, at `npc_projects/slim-m-relay/`, published through Traefik at `https://slim-m-relay.npc-server.top`.
It holds both provider credentials, bind-mounted read-only at mode 640; the image runs as `nonroot` so `group_add: ["1000"]` is what lets it read them.
`RELAY_TRUST_PROXY=true` because Traefik terminates TLS in front: without it every caller shares one rate-limit bucket and one abusive server throttles everyone.

The public name is `slim.npc-server.top`, a subdomain under the `npc-server.top` wildcard like everything else on the box.
(An earlier note here misread it as a separate `slim-npc-server.top` registration, which does not exist.)


A pinned instance runs on the owner's homelab box, deployed 2026-07-24.

- Host `npc@10.0.0.100` (Ubuntu, Docker). Stack at `/home/npc/docker-server/npc_projects/slim-m/` (`docker-compose.yml` + `.env`), following that host's one-directory-per-stack convention.
- Image `ghcr.io/nc1107/slim-m-server:latest` (the release now publishes a rolling `latest` alongside the version and sha tags), SQLite on the named volume `slim-m_slimm_data`, reachable at `http://10.0.0.100:8095`.
- Auto-updates are on: the container carries `com.centurylinklabs.watchtower.enable=true`. That host runs **exactly one** Watchtower, `scw-watchtower` in `npc_projects/scw_server/`, in label mode across every stack. Do NOT add a second Watchtower to this stack: a new instance stops the existing one on startup, which is how `scw-watchtower` briefly got killed on 2026-07-24 before being restored.
- Published at **`https://slim.npc-server.top`** through Traefik since 2026-07-25 (joined `traefik_proxy`, labels mirror the relay stack's), and still reachable on the LAN at `http://10.0.0.100:8095`.
- Verified live against 0.5.0 (auto-updated from 0.4.0 by Watchtower with no manual step, proving the pipeline): `/healthz`, `/version`, a 13-check auth and WebSocket smoke run (including a real ws hello handshake and post-deletion refusal), and a 17-check messaging run (bootstrap seeding, send, idempotent retry, list, edit, read state, sync, and the member-versus-admin permission split), plus rate limiting confirmed live (5 answered, then 429).
- Operate it with `docker compose` from that directory. It tracks `latest`; set `SLIMM_VERSION` in `.env` to a version to freeze it.

## Repository layout

```
crates/slimm-server   Rust home server (Axum + embedded SQLite via sqlx). A lib (slimm_server) plus a thin bin.
  src/                lib.rs, main.rs, config.rs, db.rs, http.rs, ids.rs, store.rs
  migrations/         forward-only sqlx migrations (0001 init, 0002 core schema)
  benches/            criterion hot-path benchmarks
  tests/              integration tests
schema/               openapi.yaml, the single source of record for the wire protocol
client/               Flutter client, a Dart native pub workspace (packages/api, design_system, data, platform, rtc, voice_canvas, app)
docker/               server.Dockerfile (multi-stage musl + distroless)
deploy/               docker-compose self-host example (server + Caddy + LiveKit + Litestream), Caddyfile, .env.example
perf/                 performance baseline model
.sqlx/                committed sqlx query cache (offline builds); regenerate after query changes
docs/                 brief, strategy, roadmap, decisions, research, design
```

## Architecture summary

- Server: Rust + Axum serving HTTP and WebSocket in one process. Embedded SQLite in WAL mode via sqlx, single serialized writer plus a read pool, all reachable to become a repository trait when Postgres is actually needed. Postgres is a documented later swap.
- Identity and ordering are two separate columns. Identity is a client-generatable UUIDv7. Order is a per-(channel, stream) monotonic `Seq`, allocated in the same transaction as the insert. Snowflake ids were rejected (single-writer needs no worker-id coordination).
- Durable writes go over idempotent REST keyed by UUIDv7; the WebSocket carries server-to-client fan-out plus ephemeral signals only.
- Wire format is schema-first JSON generated from OpenAPI plus JSON Schema, additive-only, with permessage-deflate.
- Media is self-hosted LiveKit (Opus plus VP8 simulcast). The Voice Canvas uses a per-object model with a snowflake-free per-scope op sequence.
- Security is transport-only in v1 (TLS 1.3, server holds plaintext); per-user and per-device keys are pre-wired for later opt-in E2EE DMs. Opaque session tokens (Argon2id), per-device push keys.
- Push relay is a separate stateless Go forwarder: APNs plus FCM, content-free encrypted payloads, and each device token bound to the key that registered it.

Decisions of record: [0001](docs/decisions/0001-owner-decisions.md) (owner product decisions), [0002](docs/decisions/0002-architecture-followups.md) (SQLite, same-deployment DMs, presence opt-out), [0003](docs/decisions/0003-library-decisions.md) (library choices, and a corrected Linux-media finding).

## Owner decisions to honor

Transport-only encryption in v1 (E2EE later, keys pre-wired).
The Voice Canvas is a large bounded world, not literally infinite.
No automated content or media scanning; safety is manual reporting plus report/block/moderation tooling. Target use is small self-hosted friend groups.
One backend deployment is one community. Direct messages work only between users on the same deployment in v1.
Read receipts to other users are deferred; presence has a hide/appear-offline option.
Self-hosted account recovery is an admin-issued one-time reset code (no email).
The official instance is single-process with state behind a swappable interface.
A designer review precedes design-token lock. The accent is teal, on a neutral cool-slate palette, IBM Plex Sans, border-first elevation, flat grouped messages.
The UI uses Lucide icons and never emoji as chrome. Emoji are user content (reactions) only.
Join and leave sounds default off above roughly 8 participants. The official instance publishes no moderation SLA.

## Local development

Toolchains present in this environment: cargo/rustc 1.94, go 1.26, docker, node, gh (authenticated as NC1107).
Flutter 3.44.8 stable (Dart 3.12.2) is installed at `~/development/flutter`, on PATH via `.zshrc` and `.bashrc`. `flutter doctor` reports no issues.
The host is Fedora 44 **KDE Plasma** on Wayland with an NVIDIA GPU, and the Android SDK is present with licences accepted, so Linux desktop and Android can both be built and run locally.
Android needs a JDK, and the system only ships a JRE (Fedora 44 packages no LTS `-devel` JDK, and `javac` is absent), so the first Android build fails with "does not provide the required capabilities: [JAVA_COMPILER]".
A user-local Temurin 21 at `~/.local/jdk/jdk-21.0.12+8` fixes it without root, wired in with `flutter config --jdk-dir=...`.
JDK 21 rather than the packaged 25 because that is the LTS the Android Gradle Plugin actually supports.
Two things still cannot be verified here:
- **iOS** needs macOS and Xcode, so it stays CI and TestFlight only (and that job still needs the Apple secrets).
- **Golden files** are sensitive to the engine build and font rendering, and CI generates and checks them on `ubuntu-latest` / `stable`. Run goldens locally to see failures, but regenerate them only in CI, or local and CI renders will disagree.
Fedora KDE Plasma Wayland is the Linux development and test target (owner decision, 2026-07-26), which is what this box runs. The roadmap used to name GNOME; that was corrected rather than the environment. The product still ships cross-platform, so other desktops are release targets, just not where the work is validated day to day.
`sqlx-cli` 0.8 is installed at `~/.cargo/bin`.

Everyday commands:

```bash
# Run the server
cp .env.example .env
cargo run --bin slimm-server
curl localhost:8080/healthz          # -> ok
curl localhost:8080/version          # -> {"name":"slim-m",...}

# Offline build/test (uses the committed .sqlx cache, no database)
SQLX_OFFLINE=true cargo fmt --all --check
SQLX_OFFLINE=true cargo clippy --all-targets --all-features -- -D warnings
SQLX_OFFLINE=true cargo test --all

# Container image (builds offline)
docker build -f docker/server.Dockerfile -t slimm-server:dev .

# Client (Dart pub workspace; mirrors what client-ci runs)
cd client
flutter pub get
dart analyze
dart format --output=none --set-exit-if-changed .
(cd packages/design_system && flutter test)   # tests live per package, not at the root
```

sqlx query workflow (IMPORTANT): the `query!` and `query_as!` macros are compile-time checked.
After adding or changing any macro query you MUST regenerate the offline cache, or CI and the Docker build (which run with `SQLX_OFFLINE=true`) will fail:

```bash
export DATABASE_URL="sqlite:////tmp/slimm-dev.db"     # four slashes = absolute path
( cd crates/slimm-server && sqlx database create && sqlx migrate run --source migrations )
cargo build                                            # checks queries against the db
cargo sqlx prepare --workspace                         # writes .sqlx/, commit it
```

Test databases are temp SQLite files (`Config { port, database_path }` then `db::connect`); do not use `:memory:` with the multi-connection pool.

## Contribution conventions

- Branch, then PR, then squash-merge to main. release-please plus conventional-commit PR titles.
- Commit with `git commit -s` (DCO sign-off). NEVER add an AI attribution or co-author trailer to anything.
- Never use the em dash character; use a plain dash. In long Markdown files, put each full sentence on its own physical line.
- No emoji as interface chrome (a CI gate enforces this); use Lucide icons. SPDX headers on every source file (a CI gate checks the Rust ones).
- Keep files small (a soft 300-line review budget, generated code excluded).
- Anything published under the owner's name (PR titles and bodies, issues, review comments, releases) is written in Nick's voice: read `~/.claude/Voice.md`. It is plain, hedged, anti-hype, lowercase product names, no emoji or exclamation points, and it walks through how a thing works. Commit messages, code, and working conversation stay in the normal clear register.
- Subagent model selection (from the owner's global instructions): haiku for trivial ops, sonnet for default coding and analysis, opus only for orchestration or hard reasoning; never use fable for engineering. Prefer sonnet-4-6 over sonnet-5. Workflow/Agent tooling only accepts tier aliases (haiku/sonnet/opus/fable), so full model ids cannot be passed there.
- schema/openapi.yaml is gated against the router: `crates/slimm-server/tests/openapi_contract.rs` parses the routes axum actually serves out of `src/http.rs`/`src/http/*.rs` and the paths documented under `paths:` in the schema, and fails `cargo test` (locally and in CI, via server-ci, no separate workflow to remember) if either side has something the other does not. This is why adding, removing, or renaming a route belongs in the same change as the matching edit to `schema/openapi.yaml`: the build will not pass otherwise, and the failure names the exact method, path, and file that drifted.

## CI and release, plus gotchas learned the hard way

Workflows: server-ci, client-ci, schema-ci, hygiene, perf, release. All green on main.

- Multi-arch images are built NATIVELY per architecture (ubuntu-latest for amd64, ubuntu-24.04-arm for arm64), pushed by digest, then merged into one manifest and cosign keyless-signed. No QEMU, no `cross`. The static binaries are built the same native-per-arch way. `cross` was dropped because its arm64 toolchain image hit a GLIBC mismatch.
- The Dockerfile builds natively for whatever platform buildx targets; do not reintroduce `--platform=$BUILDPLATFORM` cross-copying (it silently ships a host-arch binary in the foreign-arch image).
- `sigstore/cosign-installer` has no moving `v4` tag; pin it to an exact version (currently `@v4.1.2`). The docker/* actions do publish moving major tags, so `@v4`/`@v7` are fine there.
- Publish jobs gate on `(release-please success && released) || startsWith(github.ref, 'refs/tags/server-v')`, and server-image-merge has an explicit `if`, so re-pushing a tag can re-publish.
- `SQLX_OFFLINE: "true"` is set at the top of server-ci and perf, and in the Dockerfile builder; the `.sqlx/` cache is committed.
- release-please keeps a STANDING "release server X" PR open by design; it is the release button, not review work, and reopens after each server-affecting merge. The client was removed from `release-please-config.json` until it has real content (re-add in Phase 2), because it kept proposing a bogus client 1.0.0.
- `dart format` is strict (tall style, Flutter 3.44.x). Write short unambiguous lines; the client cannot be formatted or analyzed locally here, so CI is the check.

Environment note: the Claude Code auto-mode classifier blocks creating GitHub repositories and some repo-settings changes; the owner must do those (or grant `Bash(gh:*)`). Plain `git push` works.
The "Allow GitHub Actions to create and approve pull requests" repo setting was enabled so release-please can open PRs (`gh api -X PUT repos/NC1107/slim-m/actions/permissions/workflow -F can_approve_pull_request_reviews=true -f default_workflow_permissions=write`).

## Open items that need the owner

- **Deploy the invite gate.** The live instance at `https://slim.npc-server.top` still accepts anonymous registration and will until it runs a build containing the gate. Watchtower tracks `latest`, so cutting a release is what closes it; nothing else needs doing on the host.
- **Watch the next release PR.** `release-please-config.json` gained the `cargo-workspace` plugin so a version bump also updates `Cargo.lock`, which the new `--locked` builds require. That is the one change in the audit pass that could not be verified locally, and its failure mode is a red release PR, not a bad release.
- **`bump-minor-pre-major` is why the server stays on 0.x.** PR #42 landed as `feat!` (registration genuinely changed behaviour for a claimed deployment), and release-please read the breaking marker on a 0.x project as "go to 1.0.0" and opened exactly that PR. It was closed unmerged. The flag makes a breaking change bump the minor while under 1.0, so that reads 0.9.0 instead. 1.0 is a Phase 9 deliverable and the product is not even named yet (owner decision 9), so nothing should reach it by accident.
- **Adding Play internal testers needs the owner.** There is no Play Developer API credential anywhere: `~/.secrets/slim-m/` holds only the Firebase/FCM service account, which is scoped to messaging and cannot touch Play. Tester lists live in Play Console > Test and release > Testing > Internal testing > Testers, and each tester must then accept the opt-in link before the build appears for them.
- A real Android device test of the push path end-to-end (the last Phase 3 exit criterion with any work left).
- Reviewer protection on the `release` and `testflight` GitHub Environments (they exist but are ungated).
- Flatpak and rpm packaging manifests (`packaging/flatpak/*.yaml`, `packaging/rpm/*.spec`); the release jobs warn-and-skip until they exist.
- Optional GPG signing secret for the Linux client checksums.
- A decision on whether to keep release-please's auto-PR flow or switch to manual tag-based releases (to keep the repo at zero open PRs).
- ~~Where rendered API docs should live.~~ Settled 2026-07-26: nowhere. GitLab renders an OpenAPI file in its repo browser the way GitHub renders a README, GitHub has no equivalent, and building redoc HTML into a run artifact nobody downloads is not worth a job. The render step is gone; `redocly lint` stays, since that is the schema-ci gate. `schema/openapi.yaml` is read as the source. If a browsable copy is ever wanted: `npx @redocly/cli build-docs schema/openapi.yaml -o /tmp/api.html`.
- Linux desktop screen sharing on Wayland was written up as a blocking `flutter_webrtc` bug (issue 1542, the PipeWire/xdg-desktop-portal path not waiting for the picker response). **The owner reports getting screen share working in their own testing**, so that research finding looks stale or GNOME-specific rather than a Wayland-wide block. Treat it as probably fine and confirm in the Phase 4 spike rather than planning around a fallback. If it does break, the fallbacks are a newer flutter_webrtc, contributing the portal fix, or an X11 session.

## Parked and reference

- [docs/BACKLOG.md](docs/BACKLOG.md): accepted extra features, architectural hooks to preserve, and deliberate declines from the segment gap analysis.
- [docs/design/layout-explorations.md](docs/design/layout-explorations.md): the parked Spaces/Focus/Deck layout concepts (the sidebar layout was kept for v1).
- [docs/design/feature-exploration.md](docs/design/feature-exploration.md): the segment feature-gap analysis.
- [docs/research/](docs/research/): the specialist domain reports and adversarial reviews that fed the strategy; note that `stack-decision.md` and the fresh domain files supersede any older content.
- Interactive design mockups were published as Claude artifacts (a design proposal and a layout-explorations page).
