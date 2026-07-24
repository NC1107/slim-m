# DevOps and CI/CD Plan: Adversarial Review

Status: adversarial pre-implementation review of `docs/research/devops.md`.
Method: every claim about the two cited reference repositories was checked directly against their actual files, not taken on the specialist's word.
`echo-messenger-main.zip` was extracted from `/home/npc/Downloads/old_downloads/` and its `.github/workflows/` and Dockerfiles were read in full.
`check-in-relay` and `check-in` were read directly from `/home/npc/Documents/projects/`, including `check-in`'s real, currently live App Store and Play Store release workflow.
Findings below are ordered most severe first.

## Critical findings

### 1. The production docker-compose example omits LiveKit, the component the app's flagship feature depends on

Target: devops.md Section 5, "Production compose."

The recommended compose stack is `server`, `postgres`, and `Caddy`.
`docs/research/media.md` commits to LiveKit (self-hosted SFU) as a required third component of every self-hosted deployment, stating the stack is "Postgres plus one Rust binary plus one LiveKit binary."
`docs/research/performance.md` independently confirms this by budgeting LiveKit's idle RSS into the combined self-host memory target ("LiveKit under 50MB (media report)... a combined baseline under 200MB").
A self-hoster who follows devops.md's documented compose file literally gets a server that cannot do voice calls, screen sharing, or the Voice Canvas, the brief's stated defining feature, because the SFU it depends on was never in the file.
This is not a nitpick about a missing line; it means the production deployment story as written does not run the product.

Compounding this, `media.md` recommends LiveKit's built-in TURN server "muxed on 443... since it can share the reverse proxy's certificate."
Caddy, in the same compose file, also needs port 443 for the API and WebSocket traffic.
Two processes cannot both bind TCP 443 on one host interface.
Resolving this needs either Caddy's non-default `layer4` plugin for SNI-based TCP routing, a second public IP, or moving LiveKit's TURN listener to its own port with its own certificate, none of which is mentioned in devops.md or media.md.
Because LiveKit is missing from the compose file in the first place, this port contention is currently invisible; it will surface the first time someone actually tries to wire the two together.

Failure scenario: a self-hoster runs `docker compose up` exactly as documented, invites friends, and discovers every voice call and every Voice Canvas session fails, because there is no SFU running and, once one is added, Caddy and LiveKit fight over port 443.

Resolution: add LiveKit to the reference compose file as a first-class service before this ships as "production-ready," and resolve the TURN/TLS port-443 conflict with Caddy explicitly, either via `layer4` SNI routing or a documented second port/IP.

### 2. The plan's central "production-proven, just copy it" premise does not match either cited reference repository

Target: devops.md Section 2 ("Pipeline structure") and Section 7 ("iOS artifacts").

The report states the plan is to copy "echo's `dev-build.yml` / `release.yml`" structure, where "a `paths` job (`dorny/paths-filter`) gates each `build-*` job," and that iOS dev builds are "already" cost-gated behind `workflow_dispatch` or a `[ci-ios]` marker, calling this shape "production-proven."

Direct inspection of the extracted echo-messenger repository shows:
- There is no `dev-build.yml` file anywhere in `.github/workflows/`.
The files present are `commitlint.yml`, `e2e.yml`, `flutter-ci.yml`, `rust-ci.yml`, `security.yml`, and `release.yml`.
- There are zero occurrences of `dorny/paths-filter` anywhere in the repository.
The path gating that does exist is coarser: `flutter-ci.yml` and `rust-ci.yml` are separate workflow files, each trigger-gated on its own `paths:` list at the workflow level, not a single workflow with a shared gating job.
- `release.yml`, the file this recommendation is actually about, has no path gating at all beyond a documentation-only `paths-ignore`.
Every push to `main` that touches any code rebuilds Linux, Windows, the server binary, the Docker image, and the Web build together, unconditionally.
- There is no iOS or macOS job of any kind in echo's CI.
No cost gate exists because there is nothing to gate; echo has never built an iOS artifact in CI.

The owner's other real repository, `check-in`, which does ship to TestFlight today, tells the same story from the other direction: its `ci.yml` has no path gating whatsoever (server and app build together on every push and PR), and its actual working iOS release job uses raw `xcrun altool` with manually base64-encoded certificates and provisioning profiles decoded straight into the CI keychain, not fastlane `match` or `pilot`.
Fastlane appears in `check-in`'s `Fastfile` only for the Android Play Store lane; there is no iOS platform block in it at all.

This matters beyond pedantry.
The report's risk framing for pipeline structure and iOS CI ("already production-proven... directly serves the brief") is doing real argumentative work: it is the reason these sections carry no significant risk callout.
In fact, job-level path gating with `dorny/paths-filter`, a cost-gated iOS release path, and fastlane `match`/`pilot` are all first-time builds for this project, with zero operational history in either cited precedent.
The owner's actual working iOS pipeline (raw certs plus `altool`) is simpler and already proven, and the report never explains why it recommends replacing it with new, untested tooling instead of extending it.

Failure scenario: the first real iOS release attempt hits fastlane `match`'s git-submodule-and-passphrase workflow and App Store Connect API key setup for the first time under release pressure, with no prior internal experience to draw on, despite the report's language suggesting this is a known-good path being reused.

Resolution: rewrite Sections 2 and 7 to state plainly that job-level path gating and iOS release CI are new builds, not ports of proven infrastructure, and explicitly evaluate extending `check-in`'s working `altool`-based approach before introducing `match`.

## Major findings

### 3. release-please's "one instance, one shared version" undersells real configuration work and leaves an unanswered semantic question

Target: devops.md Section 3.

Verified against release-please's own documentation: Dart (`pubspec.yaml`) is a natively supported release-type, and a `linked-versions` plugin exists specifically to keep heterogeneous components (for example a Rust crate and a Dart package) on one shared version number.
So the mechanism the report wants is achievable, but it requires manifest mode with per-path components for `apps/client` and `apps/server` plus an explicit `linked-versions` plugin block, none of which the report specifies.
More importantly, the report never resolves the semantic question this configuration forces: should a commit that only touches the Flutter client also bump, tag, and changelog the server's version, and vice versa?
Answering "yes" (one shared version, as stated) means release notes will regularly claim a server "release" that shipped zero server changes, which is confusing for self-hosters deciding whether to upgrade their server.
Answering "no" would mean client and server drift to independent version numbers, undermining the report's own stated rationale for the shared monorepo.

Failure scenario: a self-hoster sees `v1.4.0` in the changelog with only client-side entries, upgrades their server container expecting a fix that was never in the server at all, because the shared version number implied one existed.

Resolution: pick one of the two behaviors explicitly, document it in `CONTRIBUTING.md` alongside the already-planned pre-1.0 SemVer deviation note, and specify the `release-please-config.json` shape (manifest mode, component paths, `linked-versions` group) rather than leaving it as "one instance per repo."

### 4. The relay's multi-arch build mechanism does not achieve the native-compilation goal it claims

Target: devops.md Section 4, relay multi-arch paragraph.

The report's stated rationale for the whole multi-arch section is avoiding QEMU emulation, "commonly 5 to 10x slower," and it claims the relay achieves this via "native cross-compilation" on a single amd64 runner using `docker buildx build --platform linux/amd64,linux/arm64 --push`.
That claim does not hold for the Dockerfile it would actually run against.
`check-in-relay`'s real `Dockerfile` (`FROM golang:1.26-alpine AS build`, then `RUN CGO_ENABLED=0 GOOS=linux go build ...`) has no `--platform=$BUILDPLATFORM` on its build stage and no `ARG TARGETARCH` driving `GOARCH`.
Without that specific pattern, `buildx`'s default behavior for a multi-platform build is to run the entire Dockerfile, including the Go compile step, once per requested platform, under QEMU emulation for any platform that is not the runner's native architecture.
Go's own cross-compilation is genuinely fast and needs no emulation, but only if the Dockerfile is restructured to build on the native `BUILDPLATFORM` and cross-compile via `GOARCH=$TARGETARCH`, copying the resulting binary into a final stage.
As written, the plan pays the exact QEMU tax for the relay's arm64 build that Section 4 explicitly says it is avoiding for the Rust server, just silently, because nobody profiled it.

Failure scenario: relay release builds quietly take several times longer than expected on arm64, and nobody notices because the report already told everyone this path avoids emulation.

Resolution: either restructure the relay Dockerfile with `FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS build` and `ARG TARGETARCH` plus `GOARCH=$TARGETARCH go build`, or be honest that the relay path uses QEMU too and budget CI minutes accordingly.

### 5. Watchtower auto-update is framed as an unresolved open question when the report's own primary template already answers it

Target: devops.md open questions, first bullet.

The report lists "whether the official hosted instance's deployment (watchtower-style auto-update from `:latest` versus an explicit deploy step)... belongs in this pipeline" as an open question.
`echo`'s own `infra/docker/docker-compose.prod.yml`, the exact file this report cites throughout as the validated template to extend, already runs a `watchtower` service with `WATCHTOWER_CLEANUP: "true"` and a 300-second poll interval against the official instance's own images.
The decision was already made and is running in production for the reference project this whole plan is modeled on.
Treating it as unresolved suggests the compose file was not read closely, and it leaves a real decision (should slim-m's official instance auto-update from `:latest`, with the blast-radius and rollback implications that implies, or gate deploys on the release PR merge as the report's own Section 3 argues for elsewhere) undecided by default.

Resolution: state a verdict, either adopt echo's watchtower pattern explicitly with its tradeoffs named, or reject it in favor of a release-PR-gated deploy step and say why, rather than leaving it as an open question the cited source already closed.

### 6. Signing and supply-chain section is narrower than the sibling security report already committed to

Target: devops.md Section 6.

`docs/research/security.md` states as a settled decision: "every release publishes a CycloneDX SBOM and cosign-signed GHCR images with SLSA build provenance," and separately commits to pinning GitHub Actions by commit SHA "reflecting 2025 action-supply-chain compromises."
devops.md's signing section covers cosign and SLSA provenance for images, AppImage, and rpm, but never mentions SBOM generation at all, despite it being a same-document-set commitment one report over.
It also never extends action-pinning discipline to the CI workflows it is itself designing, nor does it specify GitHub Environments with required reviewers on the jobs that actually hold publish-capable credentials: the GHCR push token, the App Store Connect API key, the fastlane `match` decryption passphrase, and the cosign OIDC identity.
These are exactly the assets a 2025-supply-chain-attack-aware plan should gate behind manual approval, and the report that owns CI design is the right place to specify that, not a cross-reference to a sibling document that does not own CI.

Failure scenario: a compromised third-party action or a leaked `match` passphrase silently ships a signed, provenance-attested, SBOM-free malicious release, because nothing in the pipeline required a human to approve the publish step or pin the actions that ran it.

Resolution: add CycloneDX SBOM generation alongside the existing cosign/SLSA steps, commit to SHA-pinned actions in this document (not just security.md), and add GitHub Environment protection rules with required reviewers on every publish-capable job.

## Minor findings

### 7. TestFlight "every tagged release" claim does not account for Apple's Beta App Review

Target: devops.md Section 7.

The report says every tagged release should produce a TestFlight build, "never cost-gated," and treats this as fully decoupled from the rest of the release pipeline.
That holds cleanly for internal testers (up to 100, no review needed), but the moment any external tester group exists, Apple's one-time (and sometimes re-triggered, on permission or entitlement changes) Beta App Review applies, with turnaround that is not fully predictable.
The report's own decoupling design (a slow TestFlight step never blocks the Linux release) already absorbs most of this risk, so it is a minor gap, but the report should say explicitly whether v1 TestFlight distribution stays internal-only to sidestep review entirely, since that is a one-line decision that removes the ambiguity.

### 8. Native arm64 runner risk note understates that this owner has zero operational history with them

Target: devops.md Section 4, risk note.

The report flags "native arm64 runners are newer than amd64 with less operational history" as the residual risk, phrased as an industry-wide observation.
Neither cited reference repository (`echo`, `check-in`, `check-in-relay`) uses arm64 GitHub-hosted runners anywhere, so the accurate framing is that this owner has no operational history with them at all, not just "less" than amd64 in the abstract.
Worth a one-line correction so the risk is not read as smaller than it is for this specific team.

### 9. Fixed per-PR CI overhead on the shared monorepo is named but never budgeted

Target: devops.md Section 1, risk note.

The report correctly flags that "client-only PRs still pay a small, fixed repo-wide CI overhead even when path-gating skips the build jobs," but never puts a number on it (checkout time, workflow-trigger evaluation, commitlint, and any always-on job), and never revisits it against the brief's own "avoid premature complexity" and "strong CI/CD" tension as the repo grows over years, which oss.md separately flags as a risk requiring deliberate maintenance.
Not a blocker at project start, but worth a concrete minutes-per-PR baseline captured early so the fixed tax is visible before it grows unnoticed.

## Summary

The two most serious problems are concrete and fixable before implementation starts: the reference compose file does not actually run the product's core feature because LiveKit is missing, and the "reuse proven CI" framing that justifies treating pipeline structure and iOS release automation as low-risk does not survive contact with either cited reference repository.
Neither finding requires abandoning the plan's overall direction (monorepo topology, release-please, GHCR multi-arch, cosign signing are all reasonable choices on their own merits), but both require the specialist to redo the risk assessment honestly: several pieces described as "already validated" are, on inspection, first-time builds, and one deployment file is missing the component the entire feature set depends on.
