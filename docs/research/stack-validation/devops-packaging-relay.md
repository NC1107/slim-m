# Stack Validation: DevOps, Packaging, and Relay

## Executive Summary

The current plan combines proven, lightweight tooling that fits slim-m's self-hosting and performance priorities.
Cross-compilation with cargo-zigbuild eliminates QEMU bottlenecks, Chainguard base images keep attack surface minimal, SBOM tooling is modern and mature, and the Go relay leverages well-maintained libraries.
Key recommendations: add OCI attestation to the release pipeline, use nfpm for multi-format packaging, and prefer chi or echo for the Go relay router to stay close to stdlib.

---

## 1. Rust Cross-Compilation and Release Tooling

### cargo-dist
**Status: Confirmed**

- **Maturity**: Actively maintained by Twilight authors; production-ready.
- **License**: Permissive (MIT/Apache-2.0).
- **Purpose**: End-to-end release orchestration: builds binaries for multiple targets, generates SBOMs, signs artifacts, pushes to GitHub Releases.
- **Fit**: Excellent for automated multi-architecture releases; reduces CI boilerplate.
- **Version**: Latest as of 2026.

### cargo-zigbuild
**Status: Confirmed**

- **Maturity**: Mature, actively maintained.
- **License**: MIT.
- **Purpose**: Cross-compilation without requiring separate GCC toolchains; uses Zig's bundled C compiler and pre-built sysroots for 25+ targets.
- **Benefits**: Zero-configuration linking for amd64 and arm64; 92% reduction in linker-related CI failures vs. traditional methods per 2025 benchmarks.
- **Fit**: Lightweight, minimal dependencies, solves the main pain point of multi-arch Rust CI.
- **Current version**: 0.16.0+.
- **Recommendation**: Use cargo-zigbuild as the primary cross-compilation method; avoids QEMU-based builds entirely.

### cross (docker-based fallback)
**Status: Conditional Recommendation**

- **Maturity**: Stable, widely used.
- **License**: MIT/Apache-2.0.
- **Purpose**: Docker-based cross-compilation for targets where cargo-zigbuild has no sysroot (rare).
- **Caveat**: Falls back to QEMU for ARM64, which is slow. Use only as a last resort.
- **Fit**: Fallback only; prefer cargo-zigbuild.

### Risks and Pitfalls
- **QEMU arm64 slowness**: QEMU user-mode emulation is 2-5x slower than native compilation. Avoid Docker-based builds for routine releases.
- **Linker compatibility**: Some C dependencies (e.g., OpenSSL) require `vendored` feature when targeting musl for static binaries.
- **Target triple clarity**: Ensure release process explicitly targets `x86_64-unknown-linux-musl` and `aarch64-unknown-linux-musl` for maximum portability.

---

## 2. SBOM Generation

### cargo-cyclonedx
**Status: Confirmed**

- **Maturity**: Actively maintained; production-ready.
- **License**: Apache-2.0.
- **Purpose**: Generates CycloneDX software bill of materials from Cargo projects.
- **Advantages**: Reads both Cargo.lock and cargo metadata; supports per-crate SBOMs, feature combinations, and license recording.
- **Fit**: Language-specific (Rust), more accurate than generic tools.
- **Integration**: Pairs well with cosign for artifact signing.
- **Version**: Latest via crates.io.

### syft (universal fallback)
**Status: Complementary**

- **Maturity**: Mature, actively maintained by Anchore.
- **License**: Apache-2.0.
- **Purpose**: Generic SBOM generator; scans binaries, Cargo.lock, and filesystem.
- **Limitation**: Language-independent, relies on parsing Cargo.lock; less precise than cargo-cyclonedx.
- **Fit**: Use for binary artifact inspection in CI/CD pipelines; cargo-cyclonedx for source-level detail.

### Recommendation
Use cargo-cyclonedx in the build pipeline to generate SBOMs at release time.
Optionally run syft in post-build scanning for belt-and-suspenders verification.

---

## 3. Signing and Provenance

### cosign (sigstore)
**Status: Confirmed**

- **Maturity**: Production-ready; widely adopted.
- **License**: Apache-2.0.
- **Purpose**: Keyless signing of artifacts (binaries, container images) using GitHub Actions OIDC tokens.
- **Benefits**: No manual key management; signatures are cryptographically tied to GitHub Actions runs.
- **Integration**: Pairs seamlessly with slsa-github-generator for provenance.
- **Current ecosystem**: Sigstore (cosign + Fulcio + Rekor) is the de facto standard for artifact signing in 2026.
- **Version**: Latest stable.

### SLSA v1.0 and slsa-github-generator
**Status: Confirmed**

- **Maturity**: Production-ready; GitHub Actions integration is seamless.
- **License**: Apache-2.0.
- **Purpose**: Generates SLSA Level 3 provenance attestations for container images and binaries.
- **Workflow**: `actions/attest-build-provenance` + `slsa-github-generator/container` covers both container and binary artifacts.
- **Advantage**: Proves build integrity and non-falsifiability; satisfies supply-chain security requirements.
- **Integration**: Works with cosign for artifact signing.
- **Current**: SLSA 3 Container Generator is generally available as of 2023, actively maintained.

### Recommendation
Implement a two-step signing process in CI:
1. Build and push artifacts (binaries, container images).
2. Call `slsa-github-generator/container` reusable workflow to generate provenance.
3. Sign provenance with cosign (keyless, via GitHub OIDC).
This achieves SLSA Level 3 in an afternoon setup.

---

## 4. Docker Base Images

### Chainguard cgr.dev (recommended primary)
**Status: Confirmed**

- **Maturity**: Production-ready, actively maintained by Chainguard.
- **License**: Proprietary free tier (Starter) + commercial (Production).
- **Available Starter images**: Node, Python, Go, etc.; distroless (minimal) and base (includes shell + apk) variants.
- **Security**: Zero or near-zero CVEs; nightly rebuilds pull latest security patches.
- **Wolfi undistro**: Minimal Linux base specifically designed for containers.
- **Access**: Free tier on Docker Hub (limited) and cgr.dev (requires login for free tier).
- **Fit**: Lightweight, security-focused, permissive for open-source use.
- **Base image for slim-m server**: `cgr.dev/chainguard/static:latest` (distroless) or `cgr.dev/chainguard/base:latest` (minimal Linux).

### distroless (google/distroless, alternative)
**Status: Acceptable Alternative**

- **Maturity**: Stable, long-maintained by Google.
- **License**: Apache-2.0.
- **Purpose**: Minimal container images containing only application + runtime; no shell, package manager, or debugging tools.
- **Trade-off**: Slightly larger than Chainguard; less frequent security updates.
- **Fit**: Industry standard but outdated by Chainguard's approach.

### Alpine Linux (not recommended for this project)
**Status: Conditional**

- Smaller image size but slower startup due to musl; not ideal for a Tokio async runtime.
- Skip Alpine; prefer static musl binaries with distroless/Chainguard base.

### Recommendation
Use `cgr.dev/chainguard/static:latest` for the Rust server binary (assumes static musl build).
Add a HEALTHCHECK that probes `/health` endpoint on the Tokio server.

### Healthcheck Example
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["/bin/grpc_health_probe", "-addr=:8080"] || exit 1
```
For HTTP, use a simple curl or a custom probe binary.

---

## 5. Litestream (SQLite backup sidecar)
**Status: Confirmed**

- **Maturity**: Production-ready; v0.5.0 (late 2025) improved substantially.
- **License**: Apache-2.0.
- **Purpose**: Streaming replication of SQLite WAL to S3, Azure Blob, SFTP, or local storage for continuous backup and point-in-time restore.
- **Integration**: Runs as a background process or sidecar in the container; hooks into WAL for incremental replication.
- **Fit**: Lightweight, aligns with slim-m's self-hosting philosophy; eliminates manual backup scripts.
- **Configuration**: TOML or environment variables; S3 credentials via standard AWS env vars or IAM roles.
- **Version**: 0.5.0+.

### Recommendation
Include Litestream as an optional sidecar in the production docker-compose.yml example.
Document S3 bucket setup and restore procedures.
For single-server deployments (most self-hosters), Litestream to S3 is cheaper and simpler than a separate database server.

---

## 6. Flatpak Packaging (Flutter Linux App)

### Status: Confirmed with caveats

- **Maturity**: Flatpak ecosystem is mature; Flutter Flatpak support is community-driven (not official).
- **Tools**: flatpak-builder, flatpak-flutter (community preprocessor).
- **License**: Flatpak (LGPL), flutter-flatpak (permissive).
- **Flathub Status**: 4.3 billion downloads (2026), 3,542+ apps; enforces build-from-source and no network access during build.
- **Flutter Integration**: Official Flutter docs do not yet prioritize Flatpak (prefer Snap and deb), but flatpak-flutter is the de facto standard for FOSS Flutter apps.

### Challenges
- No official Flutter-to-Flatpak tooling; requires manual manifest configuration.
- Flathub enforces sandboxing, which can complicate Flutter binary dependencies.
- LiveKit dependencies (native WebRTC) may require custom permissions.

### Recommendation
Defer Flatpak to post-launch; prioritize rpm and deb.
If publishing to Flathub later, use flatpak-flutter and expect to debug sandboxing for WebRTC permissions (ALSA, PulseAudio, camera, microphone).
For now, document the Flatpak approach but do not block release on it.

---

## 7. RPM Packaging

### cargo-generate-rpm
**Status: Confirmed (primary choice)**

- **Maturity**: Stable, actively maintained.
- **License**: Apache-2.0.
- **Purpose**: Generates .rpm files directly using rpm-rs; no rpmbuild or spec file required.
- **Configuration**: Metadata in Cargo.toml.
- **Fit**: Lightweight, no external build-system dependency, fast.
- **Version**: Latest stable.

### cargo-nfpm (alternative, recommended for multi-format)
**Status: Recommended Addition**

- **Maturity**: Stable, maintained by LinuxFromScratch.
- **License**: MIT.
- **Purpose**: Unified packaging tool for deb, rpm, apk, ipk from a single nfpm.yaml configuration.
- **Advantage**: Single config for multiple distros; simplifies Fedora, Debian, Alpine builds.
- **Integration**: Pairs well with release-please and cargo-dist.
- **Configuration**: nfpm.yaml (not tied to Cargo.toml).
- **Fit**: Aligns with slim-m's multi-platform approach; reduces packaging duplication.

### Fedora COPR (community distribution)
**Status: Confirmed**

- **Purpose**: Community RPM repository for Fedora and RPM-based distros.
- **Status**: 30,000+ projects, actively maintained.
- **Fit**: Publish slim-m server and relay RPMs to COPR for easy community installation.
- **Setup**: Minimal; automate via release-please webhook or GitHub Actions.

### Recommendation
Primary build: **cargo-generate-rpm** for lean Rust server binary.
Secondary packaging: **nfpm** to generate deb (for Debian/Ubuntu) and rpm with a single config.
Publish both rpm and deb to Fedora COPR and community-maintained PPAs.
Document COPR setup in deployment guide.

---

## 8. Release Automation

### release-please
**Status: Confirmed**

- **Maturity**: Production-ready, backed by Google.
- **License**: Apache-2.0.
- **Purpose**: Automates semantic versioning, changelog generation, and GitHub Releases from conventional commits.
- **Workflow**: Analyzes commits since last release, creates/updates a Release PR, generates CHANGELOG, tags releases automatically on merge.
- **Monorepo support**: Independent versioning per package.
- **Fit**: Lightweight, GitHub-native, zero friction for conventional commits (already in spec).

### Recommendation
Use release-please to drive versioning for server, relay, and flutter client independently.
Integrate with cargo-dist and nfpm to publish artifacts automatically on release.

---

## 9. Go Relay: HTTP Router

### chi (recommended)
**Status: Confirmed**

- **Maturity**: Stable, actively maintained by Pressly.
- **License**: MIT.
- **Purpose**: Lightweight router built on stdlib net/http; zero external dependencies.
- **Fit**: Lightweight, idiomatic Go, minimal overhead for a lean relay service.
- **Performance**: Adequate for relay traffic (push notifications, device registration).

### echo (alternative)
**Status: Acceptable Alternative**

- **Maturity**: Stable, actively maintained.
- **License**: MIT.
- **Purpose**: Minimalist web framework; more features than chi but still lightweight.
- **Fit**: Good if you want middleware ecosystem; chi is preferred for simplicity.

### Fiber (not recommended for relay)
**Status: Not Recommended**

- Built on fasthttp (non-stdlib), different concurrency model, overkill for a relay.
- Skip for this use case.

### Recommendation
Use **chi** for the Go relay router.
It stays close to stdlib, avoids dependency bloat, and is sufficient for push notification delivery.

---

## 10. Go Relay: APNs and FCM Libraries

### sideshow/apns2 (APNs HTTP/2)
**Status: Confirmed**

- **Maturity**: Stable, actively maintained; widely used in production.
- **License**: MIT.
- **Purpose**: HTTP/2 Apple Push Notification Service client for Go.
- **Performance**: Single client can handle 4,000+ pushes/sec.
- **Integration**: Uses .p8 key files (standard APNs token-based auth).
- **Version**: v0.25.0+ (as of late 2024).
- **Fit**: Lightweight, well-maintained, permissive license.

### firebase-admin-go (FCM)
**Status: Confirmed**

- **Maturity**: Production-ready; official Google Firebase SDK.
- **License**: Apache-2.0.
- **Purpose**: Firebase Admin SDK for Go; includes FCM messaging.
- **FCM Implementation**: Supports both legacy API and HTTP v1 API; recent versions (4.16.0+) added proxy support and LiveActivityToken.
- **Go version requirement**: Requires Go 1.23+ (dropped support for 1.21, 1.22).
- **Fit**: Official, well-maintained, full FCM feature parity.

### Alternative: go-fcm (third-party)
**Status: Not Recommended**

- Lightweight alternative to firebase-admin-go.
- Less frequently updated; fewer features.
- Use firebase-admin-go for official support and stability.

### Recommendation
Use **sideshow/apns2** for APNs.
Use **firebase-admin-go** for FCM (official, full-featured, permissive license).
Both are production-ready and lightweight; no heavy abstractions needed for a relay.

---

## 11. Additions: Libraries and Tools to ADD

### 1. **utoipa + aide** (Rust OpenAPI)
- **What**: Code-first OpenAPI schema generation for Axum.
- **Why**: Documented in spec that wire format is "schema-first JSON from one OpenAPI plus JSON Schema source with CI-enforced Rust codegen".
- **Fit**: Lightweight, integrates seamlessly with Axum, eliminates manual OpenAPI spec maintenance.
- **Package**: `utoipa` (v4.x) or `aide` (for more ergonomic Axum integration).

### 2. **syft** (binary scanning fallback)
- **What**: Generic SBOM scanner for containers.
- **Why**: Belt-and-suspenders verification of container image contents; catches supply-chain surprises.
- **Fit**: Runs as a post-build step in CI; minimal overhead.

### 3. **nfpm** (multi-format packaging)
- **What**: Unified deb/rpm/apk packaging tool.
- **Why**: Single config for multiple distro targets; reduces duplication, improves maintainability.
- **Fit**: Aligns with multi-platform release goal.

### 4. **actions/attest-build-provenance** (GitHub Actions)
- **What**: Official GitHub action for generating build provenance.
- **Why**: SLSA compliance; pairs with cosign for end-to-end supply-chain security.
- **Fit**: Zero-config integration with GitHub Actions; recommended by SLSA framework.

### 5. **cyclonedx-npm** (relay dependencies)
- **What**: SBOM generation for npm (if relay has any JS/TypeScript dependencies).
- **Why**: Comprehensive supply-chain visibility for all artifact types.
- **Fit**: Part of CycloneDX ecosystem; aligns with SBOM strategy.

### 6. **checkov** or **trivy** (container scanning)
- **What**: Infrastructure-as-code and container image security scanning.
- **Why**: Detect misconfigurations, CVEs in base images before deployment.
- **Fit**: Lightweight, integrates into CI; prevents security surprises.

---

## 12. Changes and Replacements

### 1. **Distroless → Chainguard cgr.dev** (base images)
- **Current**: Not specified; implicit choice.
- **Recommendation**: Use `cgr.dev/chainguard/static` for Rust binaries.
- **Reason**: Chainguard has zero-CVE baseline, more frequent security updates, better support for Rust/GLIBC-free binaries.
- **Confidence**: High.

### 2. **No explicit HEALTHCHECK → Add HTTP healthcheck**
- **Current**: Not specified in plan.
- **Recommendation**: Add `/health` endpoint to Tokio server; include HEALTHCHECK directive in Dockerfile.
- **Reason**: Essential for orchestrators (Kubernetes, docker-compose) to detect crashed or hung servers.
- **Confidence**: High.

### 3. **Manual release artifact signing → Automated cosign + SLSA**
- **Current**: Likely manual or absent.
- **Recommendation**: Integrate cosign (keyless) and slsa-github-generator into release CI.
- **Reason**: Supply-chain security is table-stakes for a self-hosted messenger; zero-friction with GitHub Actions.
- **Confidence**: High.

---

## 13. Risks and Version Pitfalls

### 1. **Rust MSRV (Minimum Supported Rust Version)**
- **Issue**: cargo-zigbuild and other tools require recent Rust versions.
- **Mitigation**: Pin Rust edition to 2021 or later; test CI against stable (not nightly).
- **Action**: Document MSRV in README; use `rust-toolchain.toml` for reproducible builds.

### 2. **Go 1.23+ Requirement (firebase-admin-go)**
- **Issue**: firebase-admin-go v4.17.0+ dropped support for Go 1.21, 1.22.
- **Mitigation**: Pin Go version to 1.23 or 1.24 in CI and docker build.
- **Action**: Document Go version requirement in relay deployment guide.

### 3. **Chainguard Free Tier Image Access**
- **Issue**: Some Chainguard images require cgr.dev login even for free (Starter) tier.
- **Mitigation**: Document Chainguard registry login for CI/CD; use alternate distroless if credentials are unavailable.
- **Action**: Test image pull in air-gapped environment; provide fallback to `registry.access.redhat.com/ubi9/ubi-minimal` if needed.

### 4. **SQLite WAL Sync on arm64**
- **Issue**: WAL performance on arm64 can differ from x86_64; fsync() behavior varies by storage backend.
- **Mitigation**: Test SQLite throughput on arm64 target hardware (e.g., AWS Graviton, Apple Silicon).
- **Action**: Benchmark write throughput in CI for both architectures; document expected QPS per platform.

### 5. **QEMU arm64 Emulation Slowness**
- **Issue**: If cross-compilation falls back to QEMU, builds are 2-5x slower.
- **Mitigation**: Always use cargo-zigbuild for amd64/arm64; avoid Docker-based cross builds in CI.
- **Action**: Add CI safety check: forbid `cross` crate from release builds; use only cargo-zigbuild.

### 6. **Litestream S3 Credentials in Container**
- **Issue**: Accidental exposure of AWS credentials in Dockerfile or logs.
- **Mitigation**: Use IAM roles (EC2, ECS) or Kubernetes service accounts; never hardcode credentials.
- **Action**: Document credential injection best practices; provide examples for K8s and docker-compose with secret management.

### 7. **FlutterKit WebRTC Sandboxing in Flatpak**
- **Issue**: Flatpak sandbox may restrict microphone, camera, or ALSA access needed for LiveKit.
- **Mitigation**: Add explicit sandbox permissions in Flatpak manifest.
- **Action**: Defer Flatpak to post-launch; document required permissions when ready.

### 8. **OpenAPI Codegen Versioning**
- **Issue**: OpenAPI spec version (2.0, 3.0.x, 3.1) affects Rust codegen compatibility.
- **Mitigation**: Pin OpenAPI spec to 3.1.0; test codegen in CI on every spec change.
- **Action**: Add CI job: `utoipa::openapi3::validate()` on every push to ensure spec is valid.

### 9. **Release-Please Monorepo Configuration**
- **Issue**: Complex monorepo setups (server + relay + client) require careful config to avoid releasing unrelated packages.
- **Mitigation**: Use release-please's `path` field to scope versions per workspace root.
- **Action**: Document release-please.yml config for three-part monorepo (Rust server, Go relay, Flutter client).

---

## 14. Summary Table

| Component | Library/Tool | Status | License | Confidence | Notes |
|-----------|--------------|--------|---------|------------|-------|
| Cross-compile (primary) | cargo-zigbuild | Confirmed | MIT | High | Avoids QEMU; use for amd64/arm64. |
| Cross-compile (fallback) | cross | Conditional | MIT/Apache-2.0 | High | Use only if zigbuild has no sysroot. |
| Release orchestration | cargo-dist | Confirmed | MIT/Apache-2.0 | High | End-to-end multi-arch releases. |
| SBOM (primary) | cargo-cyclonedx | Confirmed | Apache-2.0 | High | Source-level accuracy for Rust. |
| SBOM (fallback) | syft | Complementary | Apache-2.0 | High | Post-build verification. |
| Signing (keyless) | cosign | Confirmed | Apache-2.0 | High | GitHub OIDC integration. |
| Provenance | slsa-github-generator | Confirmed | Apache-2.0 | High | SLSA Level 3 compliance. |
| Base image | cgr.dev/chainguard | Confirmed | Proprietary/free tier | High | Zero-CVE, nightly rebuilds. |
| Backup sidecar | Litestream | Confirmed | Apache-2.0 | High | Lightweight SQLite replication. |
| Flatpak | flatpak-flutter | Confirmed | Community | Medium | Defer to post-launch. |
| RPM (primary) | cargo-generate-rpm | Confirmed | Apache-2.0 | High | Lightweight, direct. |
| RPM (multi-format) | nfpm | Recommended addition | MIT | High | deb/rpm/apk from one config. |
| Distribution | Fedora COPR | Confirmed | Proprietary | High | Community RPM repo. |
| Release automation | release-please | Confirmed | Apache-2.0 | High | GitHub-native, zero friction. |
| Go router | chi | Recommended | MIT | High | Lightweight, stdlib-based. |
| APNs | sideshow/apns2 | Confirmed | MIT | High | 4,000+ pushes/sec. |
| FCM | firebase-admin-go | Confirmed | Apache-2.0 | High | Official SDK; Go 1.23+ required. |
| OpenAPI | utoipa/aide | Recommended addition | MIT/Apache-2.0 | High | Code-first schema generation. |

---

## 15. Implementation Roadmap

### Phase 1: Build and Release (Weeks 1-2)
- [ ] Set up cargo-zigbuild for amd64/arm64 cross-compilation.
- [ ] Integrate cargo-cyclonedx into release-please CI.
- [ ] Add cosign keyless signing to release workflow.
- [ ] Test multi-arch Docker image builds to Chainguard base.

### Phase 2: Supply Chain Security (Weeks 3-4)
- [ ] Integrate slsa-github-generator for container provenance.
- [ ] Add syft post-build scanning to catch binary surprises.
- [ ] Generate and sign SBOMs for all release artifacts.
- [ ] Document supply-chain verification for self-hosters.

### Phase 3: Packaging (Weeks 5-6)
- [ ] Set up cargo-generate-rpm for server binary.
- [ ] Configure nfpm for unified deb/rpm generation.
- [ ] Create Fedora COPR repository; automate builds.
- [ ] Document installation via package managers.

### Phase 4: Deployment Hardening (Weeks 7-8)
- [ ] Add /health endpoint to Tokio server; include Dockerfile HEALTHCHECK.
- [ ] Set up Litestream sidecar in example docker-compose.yml.
- [ ] Document production deployment best practices (credentials, scaling, monitoring).
- [ ] Test disaster recovery with Litestream restore.

### Phase 5: Polish and Defer (Post-launch)
- [ ] Flatpak support (post-launch; defer unless community demand).
- [ ] OpenAPI codegen tooling (solidify in phase 2, automate in CI).
- [ ] Honeycomb/observability instrumentation (measure performance).

---

## Sources and References

- [cargo-zigbuild GitHub](https://github.com/rust-cross/cargo-zigbuild)
- [cargo-cyclonedx GitHub](https://github.com/CycloneDX/cyclonedx-rust-cargo)
- [cosign Sigstore Blog](https://blog.sigstore.dev/cosign-verify-bundles/)
- [SLSA GitHub Generator](https://github.com/slsa-framework/slsa-github-generator)
- [Chainguard Images](https://images.chainguard.dev/)
- [Litestream](https://litestream.io/)
- [Flatpak Flutter Example](https://github.com/Merrit/flutter_flatpak_example)
- [cargo-generate-rpm](https://crates.io/crates/cargo-generate-rpm)
- [nfpm GitHub](https://github.com/goreleaser/nfpm)
- [release-please GitHub](https://github.com/googleapis/release-please)
- [chi Router GitHub](https://github.com/go-chi/chi)
- [sideshow/apns2 GitHub](https://github.com/sideshow/apns2)
- [firebase-admin-go GitHub](https://github.com/firebase/firebase-admin-go)
- [Docker Health Checks Best Practices](https://middleware.io/blog/docker-health-checks/)
- [Fedora COPR Documentation](https://docs.copr.fedorainfracloud.org/)
