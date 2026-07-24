# DevOps and CI/CD Plan: Adversarial Review (Fresh Pass)

Status: adversarial review of `docs/research/devops.md`, checked against `docs/BRIEF.md`, `docs/decisions/0001-owner-decisions.md`, `docs/research/stack-decision.md`, and cross-checked against `docs/research/media.md`, `docs/research/appstore.md`, `docs/research/security.md`, `docs/research/networking-relay.md`, `docs/research/reference-check-in-relay.md`, `docs/STRATEGY.md`, and `docs/ROADMAP.md`.
Method: every claim in devops.md was checked against the documents it depends on or is depended on by, not accepted on its own authority.
echo-messenger was not consulted; every finding below is derived from slim-m's own documents and first principles.
Findings are ordered most severe first.

## Critical findings

### 1. devops.md is no longer in sync with STRATEGY.md and ROADMAP.md, in both directions, on foundational choices

Target: devops.md Section 3 (versioning), Section 6 (Linux artifacts), Section 4 (relay multi-arch), Section 8 (supply chain), Section "Stack interaction note."

devops.md recommends independently versioned server and client packages ("the two ship on different clocks").
STRATEGY.md (line 352) already decided the opposite: "release-please in manifest mode with component paths for server and client and a linked-versions group, so client and server share one version and change the protocol atomically," with an explicit stated rationale ("keeping their protocol versions aligned is the point").
devops.md recommends Flatpak as the primary Linux artifact with AppImage deferred.
STRATEGY.md (line 363) already decided the opposite: "Linux artifacts: AppImage primary (runs unmodified on Fedora), rpm alongside; .deb and flatpak deferred post-1.0."
devops.md's compose section assumes embedded SQLite with no separate database container, consistent with stack-decision.md.
STRATEGY.md's compose (line 358) still runs Postgres as a service ("server, postgres (small-instance tuned), Caddy... and LiveKit"), and STRATEGY.md's event-identity section (lines 18, 152-158) still uses a single global snowflake ID, not the UUIDv7-plus-per-scope-sequence scheme stack-decision.md adopted.
The direction runs the other way too: STRATEGY.md (line 360) already commits to "reviewer-gated GitHub Environments on every job holding GHCR, TestFlight, signing, or match credentials," and to structuring Dockerfiles with `FROM --platform=$BUILDPLATFORM` and `ARG TARGETARCH` "so buildx does not silently fall back to slow QEMU compilation" (line 355), and to an explicit release-PR-gated deploy step rather than watchtower (line 361).
None of these three fixes appears in devops.md's own text, so a reader of devops.md alone would not know they are already settled.

ROADMAP.md's Phase 0 task list is written against the STRATEGY.md version of these decisions (linked-versions, Postgres via the stack it inherits, snowflake IDs), not against devops.md and stack-decision.md's fresher choices.
There is currently no single document an implementer can follow start to finish without hitting a contradiction: reading devops.md and stack-decision.md gives one system (SQLite, UUIDv7 plus sequence, independent versions, Flatpak-first), reading STRATEGY.md and ROADMAP.md gives a different one (Postgres, snowflake IDs, linked versions, AppImage-first).

Failure scenario: an implementer opens ROADMAP.md, the literal Phase 0 execution checklist, and builds the Postgres-backed, snowflake-ID, linked-version, AppImage-first system it describes, discarding this entire fresh devops.md and stack-decision.md pass without anyone deciding that was the intent.
Alternatively, an implementer follows devops.md and stack-decision.md and ends up silently contradicting the rationale STRATEGY.md already recorded for the opposite choices, with no document explaining why the newer choice should win.

Resolution: before any implementation starts, explicitly reconcile devops.md and stack-decision.md against STRATEGY.md and ROADMAP.md.
Either update STRATEGY.md and ROADMAP.md to adopt the fresher SQLite, UUIDv7-plus-sequence, independent-versioning, and Flatpak-first decisions with stated rationale for reversing the earlier calls, or update devops.md to fall in line with STRATEGY.md's already-reasoned choices.
Either way, pull STRATEGY.md's already-solved deploy-step, BUILDPLATFORM/TARGETARCH, and GitHub Environments decisions into devops.md's own text so the specialist document is self-sufficient and does not silently depend on a narrative document a future contributor may never read.

## Major findings

### 2. The LiveKit TURN/TLS-on-443 versus Caddy-on-443 conflict is still unresolved in devops.md's own text

Target: devops.md Section 5.

media.md commits to LiveKit's built-in TURN server "muxed on 443... since it can share the reverse proxy's certificate."
The same compose example also runs Caddy for automatic TLS, which needs port 443 for the app server's API and WebSocket traffic.
Two processes cannot both bind TCP 443 on one host interface without SNI-based routing.
devops.md's own text only says "explicit UDP port range or host networking documented for LiveKit's TURN/media path," which addresses the UDP media path but never mentions port 443 or the TCP contention at all.
STRATEGY.md (line 358) says this was resolved "as described in the media section," but devops.md, the document that actually owns the compose file, still does not state the resolution (layer4 SNI passthrough, a second port, or a second IP).

Failure scenario: a self-hoster follows devops.md's compose description literally, and any client on a network that requires TURN-over-TLS to traverse a restrictive firewall fails to establish voice or canvas media, because LiveKit's TLS-muxed TURN listener never got a port.

Resolution: state the concrete resolution in devops.md itself: Caddy owns 443 for the app API, LiveKit's TURN/TLS runs on its own documented port with a UDP range, and SNI passthrough or a second IP is documented as the advanced option for operators who need TURN specifically on 443.

### 3. The relay's "cross-compile from one amd64 runner" claim has no stated mechanism to actually avoid QEMU

Target: devops.md Section 4.

The stated rationale for the whole multi-arch section is avoiding QEMU, "5 to 10x slower" for Rust, and native per-arch runners are correctly used for the server.
For the relay, devops.md says only "the Go relay cross-compiles fast enough that one amd64 runner... suffices," with no mention of `FROM --platform=$BUILDPLATFORM` on the build stage or `ARG TARGETARCH` driving `GOARCH`.
Without that specific Dockerfile pattern, buildx's default multi-platform behavior runs the entire Dockerfile, including the Go compile step, once per requested platform under QEMU for any non-native platform, so the claimed "cross-compile" is not guaranteed by anything stated.
ROADMAP.md's Phase 0 bullet already commits to this exact `FROM --platform=$BUILDPLATFORM` / `ARG TARGETARCH` pattern for multi-arch publishing, but devops.md's own relay paragraph does not carry that detail forward, so a reader relying on devops.md alone would not know the pattern is required.

Failure scenario: relay arm64 builds silently run under QEMU emulation, taking several times longer than expected, and nobody notices because the surrounding text already asserts this path avoids emulation.

Resolution: state explicitly in devops.md that both the server and relay Dockerfiles must use `FROM --platform=$BUILDPLATFORM` on the build stage and `ARG TARGETARCH` to drive the target architecture, not just the server.

### 4. No build-time ownership fix for the SQLite data directory under a nonroot distroless runtime

Target: devops.md Section 5.

The runtime image is `distroless/static-debian12:nonroot`, which runs as a fixed non-root UID, and the server owns its SQLite file directly on a named Docker volume.
Docker seeds a freshly created named volume from the image's contents and permissions at that mount path, and a distroless image has no shell or tooling to fix ownership after the fact.
check-in-relay, an allowed reference for the relay only, already solved exactly this problem by pre-creating and chowning its data directory to the nonroot UID at build time, but devops.md's server Dockerfile section never mentions doing the same for the server image.

Failure scenario: a self-hoster runs `docker compose up` for the first time on a brand new volume, and the server fails its very first SQLite write with a permission error, because the volume was seeded with the wrong ownership and nothing in the image corrected it.

Resolution: pre-create and chown the data directory to the nonroot UID in the server Dockerfile's build stage, exactly as check-in-relay already does, and state this explicitly in devops.md rather than leaving it implicit.

### 5. No GitHub Environments or required-reviewer gate on publish-capable jobs, in devops.md's own text

Target: devops.md Section 8.

devops.md commits to SHA-pinned actions, cosign keyless signing, SLSA provenance, and Buildx-native SBOMs, a real and coherent supply-chain story.
Nothing in that section requires a human approval step on the jobs that actually hold publish-capable credentials: the GHCR push token, the App Store Connect API key, the fastlane match decryption passphrase, and the cosign OIDC identity.
STRATEGY.md (line 360) already commits to "reviewer-gated GitHub Environments on every job holding GHCR, TestFlight, signing, or match credentials," but devops.md's own supply-chain section does not state this, so a reader of the specialist document alone would conclude signing and provenance are the whole story.

Failure scenario: a compromised third-party dependency or a malicious contributor PR merges cleanly, and CI auto-publishes a fully signed, SBOM-attached, provenance-attested release with no human ever approving the actual publish step, because pinning and signing were mistaken for a complete control.

Resolution: add GitHub Environment protection rules with required reviewers on every job that touches a publish-capable credential, stated in devops.md itself, not only cross-referenced from a sibling document.

### 6. Squash-merge PR-title enforcement depends on an unstated, non-default repository setting

Target: devops.md Section 2.

devops.md enforces Conventional Commits on the PR title, reasoning that "squash-merge collapses commit history anyway, so the squash message is what actually becomes the changelog entry."
That reasoning only holds if the repository's squash-merge default commit message is explicitly configured to be the pull request title.
GitHub's squash-merge default commit message option is a per-repository setting with several choices, and the option that combines all constituent commit messages is a common default that does not equal the PR title.
devops.md never states that this setting must be changed, so the linted PR title and the string release-please actually parses from the squash commit can silently diverge.

Failure scenario: a PR titled `feat: add read-state sync` squash-merges with a commit body assembled from several messy in-progress commit messages instead of the linted title, and release-please's changelog and version bump are driven by that assembled body rather than the reviewed, Conventional-Commit-compliant title.

Resolution: state explicitly in devops.md that the repository's squash-merge default commit message must be set to the pull request title, as part of repo setup, not left as an implicit assumption.

### 7. The release-please configuration for two independently versioned packages sharing one `schema/` directory is never specified

Target: devops.md Section 1 and Section 3.

Section 1's own rationale for the monorepo is that a wire-protocol change touches `schema/`, generated Rust types, and generated Dart types together.
Section 3 then commits to independently versioned server and client packages via release-please manifest mode, without specifying the `release-please-config.json` component paths, or how a commit whose real content is a shared-schema change should be attributed to one or both packages.
Manifest mode's correctness for a shared-directory, multiple-independently-versioned-package layout is a genuinely nontrivial configuration to get right, and devops.md gives no concrete shape for it.

Failure scenario: a schema-breaking commit is scoped or path-matched in a way that only bumps one package's version, so a self-hoster reads a patch-level server bump and upgrades without realizing the wire protocol changed underneath them, defeating the stated reason for overriding SemVer's pre-1.0 freeze in the first place.

Resolution: specify the actual `release-please-config.json` component and path shape in devops.md, including how `schema/`-only and dual-touching commits are attributed, and add a CI check that a schema-affecting commit always triggers a version-eligible change in both packages.

### 8. No CI job actually boots the published compose stack end to end

Target: devops.md Section 5 and Section 2.

devops.md's pipeline runs format, lint, and unit and integration tests per language, plus a schema-drift check, but nothing runs `docker compose up` against the actual published server, LiveKit, and Caddy services and asserts a healthy multi-service startup.
This project has already shipped one docker-compose draft that omitted LiveKit entirely and would not have run voice at all, caught only by a prior manual adversarial read, not by CI.
The port-443 conflict in finding 2 above is the same class of bug: something that only surfaces the first time someone actually runs the compose file, which nothing in the pipeline currently does automatically.

Failure scenario: a future change silently breaks the compose file, for example a renamed environment variable or a removed healthcheck dependency, and it ships to self-hosters undetected because no CI job ever exercises the file the way a self-hoster actually would.

Resolution: add a periodic or pre-release CI job that runs the published compose file against the just-built images, waits for all services to report healthy, and performs a minimal smoke test (a login or a WebSocket connect) before a release is considered complete.

### 9. Flatpak-primary does not address sandbox GPU access, remote-hosting burden, or the COPR alternative

Target: devops.md Section 6.

The stated risk is narrow: "flatpak sandboxing can clip global hotkeys or deep tray integration."
Voice calls, screen share, and the Voice Canvas are the brief's flagship feature and depend on hardware-accelerated video decode; Flatpak's sandbox restricts device access, including `/dev/dri` for GPU decode, unless the manifest explicitly grants it, and devops.md's risk note never mentions this axis at all despite it directly touching the brief's performance-first requirement.
Publishing "a self-hosted static Flatpak remote from day one" is new, ongoing maintainer infrastructure, an OSTree repository with GPG signing, summary regeneration, and hosting, none of which is budgeted as an operational cost anywhere in the document.
Fedora's own COPR service offers free, GPG-signed, multi-Fedora-version RPM hosting with none of that new infrastructure to build, and devops.md never evaluates it as an alternative to hand-rolling a Flatpak remote, despite Fedora being the named primary desktop target.

Failure scenario: screen share or the canvas stutters badly on Fedora specifically, the primary desktop testing platform, because the sandbox denied GPU device access and nobody validated decode performance inside the Flatpak sandbox before committing to it as primary.

Resolution: validate hardware decode inside the Flatpak sandbox (the `--device=dri` portal or static permission) as part of the same early spike media.md already recommends for Fedora, and evaluate COPR as a lower-maintenance-burden alternative or complement to a self-hosted Flatpak remote.

### 10. Binary and image size, an explicit brief performance requirement, has no CI budget or gate anywhere in the pipeline

Target: devops.md, entire document.

The brief names "Binary size" explicitly under Performance Requirements, alongside memory, CPU, and startup time.
performance.md tracks concrete CI-gated budgets for cold start, warm start, memory, and frame time, but devops.md, the document that owns artifact publishing, never states a container image size or client binary size budget, nor a CI step that measures or gates either over time.

Failure scenario: the server image or a packaged Linux artifact grows steadily over many releases as dependencies accumulate, and nobody notices because nothing in CI measures or reports the trend, until a self-hoster on constrained storage or bandwidth complains.

Resolution: add an image-size and packaged-artifact-size measurement to CI, versioned alongside the other performance baselines performance.md already establishes, with a percentage-regression gate consistent with the 5 percent size-regression threshold performance.md sets for the client.

## Minor findings

### 11. "macOS runners cost roughly ten times a Linux runner" misstates the actual constraint for a public repository

Target: devops.md Section 7.

GitHub Actions minutes, including macOS runners, are free and effectively unlimited for public repositories regardless of runner OS; the stated multiplier only translates into real dollar cost on a private repository.
The actual constraint behind gating iOS PR builds behind manual dispatch is runner queue time and contention, not spend.
This distinction matters if the repository is ever made private, for example during a coordinated security disclosure, at which point the cost framing becomes suddenly and unexpectedly literal.

Resolution: restate the rationale as runner availability and CI feedback latency, not cost, and note the real cost exposure that would appear if the repository ever goes private.

### 12. The official instance's deploy trigger is left fully open, not even a stub reference

Target: devops.md, open questions, and the "Stack interaction note."

devops.md correctly identifies that the official instance's deploy step, pull the new tag and restart, is better suited to an operations runbook than the CI/CD pipeline, but no such runbook exists yet in `docs/`, and the open question is left unresolved rather than pointing to a placeholder.
STRATEGY.md (line 361) already states a verdict, an explicit deploy step gated on release-PR merge rather than watchtower auto-update, but that verdict is not reflected back into devops.md.

Resolution: either absorb STRATEGY.md's already-stated deploy-step verdict into devops.md directly, or create the operations runbook document devops.md gestures at, so the pipeline's endpoint is not simply undefined.

### 13. Independent per-package version numbers do not encode cross-package protocol compatibility

Target: devops.md Section 3.

The stated reason for overriding release-please's pre-1.0 SemVer freeze is that "self-hosters upgrading a running server need a real compatibility signal from day one."
An independent SemVer bump on the server package signals that the server changed relative to its own prior version, not that the currently installed client remains compatible with it.
stack-decision.md's own wire format already carries a protocol version in the WebSocket envelope, but nothing in devops.md ties that protocol version to release notes or exposes it anywhere a self-hoster deciding whether to upgrade would see it.

Resolution: surface the wire protocol's envelope version number in each release's changelog entry, so a self-hoster can check compatibility directly instead of inferring it from an independent SemVer number that was never designed to carry that information.

## Summary

The most consequential problem is not a technical defect inside devops.md, it is that devops.md no longer agrees with the project's own downstream planning documents on versioning strategy, Linux packaging format, and, by way of stack-decision.md, the database engine and event-identity scheme, while ROADMAP.md's Phase 0 checklist is written against the older set of choices.
Several smaller gaps follow a consistent pattern: a detail STRATEGY.md already resolved, port 443 contention, the BUILDPLATFORM cross-compile pattern, GitHub Environments, and the deploy-step verdict, is present in the narrative document but absent from devops.md's own text, so the specialist document a future contributor implements from is not self-sufficient.
The remaining findings are concrete, fixable gaps in devops.md considered on its own terms: an unaddressed volume-permission gotcha that would break a self-hoster's first deploy, a supply-chain story with signing but no human approval gate, a Conventional Commit enforcement mechanism that depends on an unstated repository setting, an underspecified multi-component release-please configuration, no automated test of the compose file it ships, an unexamined GPU-sandboxing risk for the flagship feature on the primary desktop target, and no CI budget for a performance axis the brief names explicitly.
None of these individually require abandoning devops.md's overall direction, monorepo topology, release-please, GHCR multi-arch, and cosign signing are all reasonable choices on their own merits, but the plan cannot be called settled until devops.md and stack-decision.md are explicitly reconciled with STRATEGY.md and ROADMAP.md, in both directions, before Phase 0 implementation begins.
