# CI/CD and Release Automation

Status: pre-implementation research.
Scope: repo topology and pipeline structure for the client, server, and relay, conventional commit enforcement, automated versioning and GitHub Releases, GHCR multi-arch image publishing, a production Dockerfile and docker-compose example, Linux and iOS artifact building and signing, and CI caching.

## 1. Repo topology: one monorepo for client and server, the relay stays separate

Verdict: client and server live in one repository, following echo's `apps/server` / `apps/client` layout (Rust workspace, Melos-managed Flutter workspace).
The relay is a separate repository, mirroring check-in-relay's real relationship to check-in.

Rationale: client and server change together constantly, since a new WS event kind touches both sides of the wire protocol in one PR, so one repo keeps changes atomic, the same problem echo's monorepo already solves.
The relay should stay a dumb, minimal forwarder that changes rarely on its own schedule; coupling its release cadence to Flutter/Rust CI would fight its own "kept intentionally minimal" design goal.

Alternatives rejected: three separate repos turns every wire-protocol change into a multi-repo PR, a real tax for no benefit at this size.
One repo for all three was rejected for the reason above; check-in-relay's own separation from check-in is direct precedent for the split.

Risk: client-only PRs still pay a small, fixed repo-wide CI overhead even when path-gating skips the build jobs.

## 2. Pipeline structure: echo's path-gated shape, minus its two real gaps

Verdict: copy echo's `dev-build.yml` / `release.yml` structure almost unchanged: a `paths` job (`dorny/paths-filter`) gates each `build-*` job by files actually touched, `lint-test-rust`/`lint-test-flutter` run independently and gate only their own platform, and iOS dev builds stay cost-gated behind `workflow_dispatch` or a `[ci-ios]` marker since macOS runners cost roughly 10x Linux.
This shape is production-proven and serves the brief's "strong CI/CD" principle directly.

Two gaps should not carry forward: echo's version job always bumps patch regardless of commit type, matching neither its own commit-type table nor this brief's "feat bumps feature, fix: patch, breaking: major" (Section 3 fixes this), and echo's Docker publish jobs never set `platforms:`, so its images are amd64-only despite Buildx being wired up (Section 4 fixes this).

Relay CI: `go build`, `go vet`, `go test ./...`, `golangci-lint`, `govulncheck` on every push, no path gating needed given the repo's small size, finishing in well under two minutes.

## 3. Versioning: release-please, not semantic-release, not a hand-rolled tag script

Verdict: `googleapis/release-please-action`, one instance per repository (client/server monorepo shares one version number; the relay versions independently).

Rationale: release-please parses conventional commits into the exact `feat`/`fix`/`breaking` to `minor`/`patch`/`major` mapping the brief describes, via a merge-gated release PR that accumulates a changelog rather than tagging silently on push.
That merge gate suits a project valuing maintainability over speed: merging "Release vX.Y.Z" is a deliberate act, and a natural point to edit release notes before they reach users.
It needs no custom tag-reservation bash and creates the GitHub Release directly, so "GitHub Releases driven versioning" is literal rather than glued together.

Alternatives rejected: semantic-release is heavier for no added benefit; its Node-centric plugin chain and changelog-first bias fit a JS project better than a Rust/Flutter/Go one.
Echo's hand-rolled tag script was rejected as a template: it works, but per the gap above it does not branch on commit type, so it would need a rewrite anyway.

Concrete pre-1.0 call the brief leaves implicit: set `bump-minor-pre-major: true` and `bump-breaking-pre-major: true`, so `feat`/breaking commits bump minor/major even before 1.0.0, overriding release-please's default of freezing the major digit at 0.
Rationale: self-hosters need real compatibility-break signals from day one, the brief's own intent.
Risk: a deliberate deviation from strict SemVer convention; document it once in `CONTRIBUTING.md`.

Publishing stays decoupled from the tag, following echo's own `linux-packages.yml` principle that a packaging hiccup must never block the main release: the tag/Release job is one step, each artifact job triggers independently off `release: published`, so a slow TestFlight review never blocks a Linux user's release.

## 4. GHCR publishing: real multi-arch, not echo's amd64-only default

Verdict: publish `linux/amd64` and `linux/arm64` manifests for both server and relay images.

Rationale: the brief's target self-hoster ("a handful of users") very often means a Raspberry Pi or other arm64 board, so amd64-only is a real gap.
For the Rust server, build each arch natively on GitHub's free-tier `ubuntu-24.04-arm` runners rather than cross-compiling under QEMU, commonly 5 to 10x slower for Rust; a matrix of native per-arch builds pushes per-arch tags, then a final job merges them with `docker buildx imagetools create`.
For the Go relay, native cross-compilation (`GOARCH=arm64 CGO_ENABLED=0`) is fast enough that one amd64 runner with `docker buildx build --platform linux/amd64,linux/arm64 --push` is sufficient.

Risk: native arm64 runners are newer than amd64 with less operational history; QEMU emulation remains a working, slower fallback for the server image.

## 5. Production Dockerfile and docker-compose

Server image: two-stage build, `rust:<pinned>-bookworm` builder targeting the musl target (`x86_64`/`aarch64-unknown-linux-musl`) with `rustls`, no OpenSSL, reusing echo's dummy-skeleton dependency-caching trick.
Runtime: `gcr.io/distroless/static-debian12:nonroot`, the base check-in-relay already validates, non-root, no shell.
If a subprocess (ffmpeg-style media handling, as echo needs) turns out to be required, switch to `distroless/cc-debian12` plus `tini`; otherwise Axum's own graceful shutdown is enough and tini can be dropped.
Target: sub-20 MB compressed, under backend.md's 40 MB ceiling.

Compose example: `server`, `postgres` (small-instance-tuned `postgresql.conf`), and Caddy for automatic TLS, matching the check-in-relay pattern the security research already commits to, rather than Traefik's extra surface for a single-instance self-hoster.
`mem_limit` values reflect backend.md's under-150 MB combined idle target; document a Traefik fallback in the README, mirroring check-in-relay's own.

## 6. Linux artifacts: AppImage first, rpm alongside, signed with cosign

Verdict: AppImage as the primary artifact, .rpm alongside it, defer .deb and flatpak.

Rationale: AppImage needs no per-distro packaging maintenance and runs unmodified on Fedora, the brief's stated primary test environment, without existing in any repository, the lowest-maintenance path to every Linux user.
.rpm ships alongside it because Fedora users expect a native `dnf`-installable package; echo's `fpm`-based script is a reasonable base to extend with AppImage generation.
Flatpak is rejected for now: Flathub submission and sandboxing add real CI and maintenance overhead, and LiveKit's native device and screen-share portal access would need extra permission work, for a discoverability benefit that matters more once the app has an established base; revisit post-1.0.

Signing: `cosign` keyless signing (Sigstore, OIDC-backed to the GitHub Actions identity) across every artifact type, images, AppImage, and rpm, one signing story instead of three, and no long-lived private key sitting in Actions secrets.
Also generate SLSA provenance via `actions/attest-build-provenance`, low effort for meaningfully higher trust.
Risk: cosign verification is not yet a habit for most Linux desktop users; publish a conventional detached GPG signature and SHA256SUMS alongside it so both paths exist.

## 7. iOS artifacts: fastlane match plus pilot to TestFlight

Verdict: fastlane `match` for certificates/profiles (encrypted in a private git repo, not raw files in GitHub secrets), fastlane `pilot` to upload to TestFlight, authenticated with an App Store Connect API key rather than a personal Apple ID, on GitHub-hosted macOS runners.
Unlike dev builds, release-pipeline iOS builds are never cost-gated: the brief names iOS a primary testing platform, so every tagged release should produce a TestFlight build, while dev-branch cost-gating stays for day-to-day pushes.
Full App Store review readiness, including the invite-only account model backend.md flags as an open guideline question, is separate from TestFlight and does not block this pipeline.

## 8. Caching

Reuse echo's validated shape as-is: `Swatinem/rust-cache`, `~/.pub-cache` plus `.dart_tool` keyed on `pubspec.lock`, Gradle caches, CocoaPods caches, and `type=gha` Docker layer caching.
Add Go's built-in module/build cache (`actions/setup-go`'s `cache: true`) for the relay.
Do not reach for self-hosted or larger runners at project start; echo's own numbers (5 to 10 minutes saved on warm Rust jobs) show standard caches already solve most of the cost, and paying for bigger runners before queue time is a proven bottleneck is the premature complexity the brief warns against.

## A brief mistake worth flagging

The brief's versioning examples describe full SemVer behavior but never state a starting version or pre-1.0 behavior, and echo's own reference implementation, read closely, does not actually implement commit-type-aware bumping at all.
Copying echo's version job verbatim would silently fail to deliver what the brief itself asks for; Section 3 resolves this concretely rather than leaving it as a surprise discovered after the first breaking change ships as a patch release.

## Open questions

- Whether the official hosted instance's deployment (watchtower-style auto-update from `:latest` versus an explicit deploy step gated on the release PR merge) belongs in this pipeline or is a separate operations concern.
- Whether flatpak should be scheduled for a specific post-1.0 milestone now, or decided once real Flathub demand appears.
