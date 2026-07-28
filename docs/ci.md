# CI and the release pipeline

Why the workflows in `.github/workflows/` are shaped the way they are.

A YAML file has no doc-comment mechanism, so a `#` block is the only thing a workflow can carry, and this repo caps a plain comment at two lines.
Anything that needs more room than that lives here, and the workflow keeps a two-line note pointing at the section.
Each section below is named for its workflow file.

## Workflows at a glance

| Workflow | Runs on | What it gates |
| --- | --- | --- |
| `server-ci` | changes under `crates/`, `schema/openapi.yaml`, the Cargo files, `rust-toolchain.toml`, `docker/server.Dockerfile` | fmt, clippy, tests, release build, binary size budget |
| `client-ci` | changes under `client/` | dart analyze, format, every package's tests |
| `client-ios-ci` | changes under `client/packages/app/ios/`, `rtc/`, `platform/`, the pubspec files; every push to `main` | the iOS CallKit XCTest on macOS, and the extension-embeds-no-frameworks check |
| `schema-ci` | changes under `schema/`, `redocly.yaml` | redocly lint, and the additive-only oasdiff gate on pull requests |
| `hygiene` | every push and pull request | iOS purpose strings, no emoji in UI source, SPDX headers on Rust source |
| `perf` | changes under `crates/`, `perf/`, the Cargo files; plus published releases | benches compile on PRs, benches run on a release |
| `compose-smoke` | changes to the self-host stack, plus a weekly schedule | `docker compose up` on a fresh box produces a working deployment |
| `push-relay-contract` | changes to the server's push path | a server-generated envelope through the relay repo's real HTTP handler |
| `release` | pushes to `main`, and `server-v*` / `client-v*` tags | the whole publish pipeline |

## server-ci

Path-gated so a client-only change never triggers a server build.

`schema/openapi.yaml` is in the path filter even though it is not Rust.
`crates/slimm-server/tests/openapi_contract.rs` gates the schema against the router, so a schema-only edit that documents a path nothing serves, without touching `crates/`, must still run that test.

`SQLX_OFFLINE: "true"` is set workflow-wide: the crate compiles against the committed `.sqlx` query cache and needs no database in CI.

The binary size budget step exists because the brief treats binary size as a first-class budget rather than something to notice after the fact.

## client-ci

Path-gated so a server-only or schema-only change never triggers the Flutter client build.

### Goldens are not a separate job

Golden-file assertions (`matchesGoldenFile`) live inside each package's ordinary `flutter test` suite, not in a job of their own.
Golden PNGs are sensitive to the exact Flutter engine and Skia build and to font rendering, so goldens are generated and verified on the same `stable` channel on `ubuntu-latest`.
If goldens start flaking across runs, pin an exact Flutter version in the workflow instead of floating on `stable`, and regenerate the goldens with `flutter test --update-goldens` on that same pinned version so both sides render identically.

### The iOS unit-test job, and why it is its own workflow

The CallKit synchronous-report invariant is a real termination risk, not a style rule.
iOS kills an app that takes a VoIP push without reporting a call before the handler returns, and repeat offences cost it VoIP push entirely.
That makes it worth a macOS runner of its own, because the ubuntu job runs Dart tests and cannot compile a line of Swift.

It is simulator only, so it needs no signing identity and no secrets: it compiles the Swift and runs XCTest, it does not produce a shippable build.
The signed device build stays in the release workflow.

It lives in `client-ios-ci.yml` rather than beside the Dart job because it is the expensive one by an order of magnitude: 14 minutes against 5, measured across recent runs, which made `client-ci` a median of 11 minutes when the Dart half finishes in a third of that.
A GitHub workflow cannot path-filter one job, so the split is what lets it be gated on the paths that can actually change its answer: the iOS project, the plugins carrying CallKit and WebRTC, and the dependency set, which is how a Dart-side change reaches an Xcode build.
Every push to `main` runs it whatever changed, so `main` is never trusted on a path filter alone.
CocoaPods is cached on the lockfiles, since rebuilding those pods is most of what the project-generation step spends its five minutes on.

`flutter build ios --simulator --no-codesign` runs first because xcodebuild needs the generated Flutter config and the plugin registrant to exist before the project will open, and only a Flutter build makes them.
`--no-codesign` keeps it to compiling, with no identity involved.

The simulator is chosen from what the runner actually has rather than by name.
A hardcoded `iPhone 16` broke the first time this ran, and it would break again silently every time GitHub rolls the image forward.

## schema-ci

The breaking-change gate runs only for `pull_request` events.
Diffing only makes sense against a PR's base branch, and a push to `main` has no other side to diff against; a push to `main` is covered by the lint job and skips the diff entirely.

The PR's head commit is checked out explicitly rather than the default merge-ref checkout, so `HEAD:schema/openapi.yaml` is exactly the schema the PR proposes with no synthetic merge commit in between.

oasdiff also needs the base branch's schema content, but that checkout only fetched the PR head commit.
The workflow fetches just that one base commit, shallowly, by its exact SHA from the `pull_request` event payload, so it lands in the local object database without cloning the base branch's history.
oasdiff then reads it straight out of git as `<base-sha>:schema/openapi.yaml`.

`oasdiff breaking` reports only changes that break existing clients: removed paths and fields, narrowed types, newly required properties, and similar.
Purely additive changes such as a new optional field or a new endpoint are not breaking and pass, which is what makes this gate additive-only by construction.

### The one OpenAPI 3.0 `nullable` in the schema

`RegisterRequest.invite_code` in `schema/openapi.yaml` is written with the OpenAPI 3.0 `nullable` keyword, alone in a 3.1 document.
oasdiff cannot read a 3.1 `type: [x, "null"]` union and reports the conversion as the property losing nullability, which fails the additive-only gate, and redocly rejects carrying both forms at once.
It is a request property, so nothing is testable either way: the field is optional through `required` regardless, and the server takes an absent value and an explicit null identically.

## hygiene

### iOS purpose strings

App Store review rejects a binary whose linked SDKs reference a sensitive API without a purpose string, and it does it asynchronously.
altool uploads, the job goes green, and the rejection arrives by email some minutes later.
This gate turns that into a red PR instead.

### No emoji in UI source

Emoji are user content (reactions), never interface chrome; chrome uses Lucide icons.
The gate fails on any emoji codepoint in client source.
It matches text sources only and passes `--binary-files=without-match`, so a compiled artifact that happens to contain those bytes cannot trip it.

## perf

Path-gated to server and perf-scaffolding changes.
GitHub Actions does not support path filters on the `release` event, so the release-triggered job is not path-gated; it only ever runs once per published release regardless.

`compile-gate` is a fast compile-only gate on every pull request: it proves the benchmarks still build without paying for a full measurement run on each push.

`benchmark` runs the real benchmarks once a release is published and uploads the criterion report as a workflow artifact, for hand-curation into a new `perf/baselines/<version>.json` (see `perf/README.md`).
It has no environment gate, and that is deliberate: it uploads only an intra-run workflow artifact, not a published release asset, so it is exempt for the same reason the release workflow's `server-binaries` build stage is.
Reviewer-gated Environments are applied at the true publish boundary (GHCR push, release assets, TestFlight), not to build-time artifacts.
No secrets are used.

## compose-smoke

The self-host stack is the product for most people, and nothing was checking that it boots.
Every other gate tests the server, the client or the schema in isolation; this one asks whether `docker compose up` on a fresh box actually produces a working deployment, which is the thing a self-hoster does first and the thing most likely to rot silently when a service is added.

It runs on changes to the stack itself and on a weekly schedule, because the failure mode it catches is usually an upstream image moving rather than a commit here.

### Building the image locally

The published image is only correct for `main`.
On a PR that changes the Dockerfile the whole point is to boot what that branch would produce, so the image is built locally under the tag `SLIMM_VERSION=smoke` resolves to, and compose uses it instead of pulling.

### Refusing to start without LiveKit credentials

`deploy/.env.example` ships `LIVEKIT_API_KEY` and `LIVEKIT_API_SECRET` empty on purpose.
Compose must refuse and name the missing one rather than starting an SFU anybody can mint tokens for, and that refusal is worth a test of its own because it is a security property, not a convenience.

Either variable name is a correct refusal: compose stops at the first variable it interpolates, and that order is not ours to fix.

### What the smoke run covers, and why only part of the stack

Caddy wants ports 80 and 443 and a real domain to get a certificate, and neither is available on a runner, so the smoke test covers the two services that carry the product: the server and the SFU.
The values written into `.env` are real-looking so the config renders; nothing there is reachable from outside the runner.

The server image ships no shell, so `/version` is asked for from the host through a throwaway container on the same network rather than by exec-ing into it.

`voice enabled` in the server log is the regression check for a real gap: the compose file ran an SFU for months without ever telling the server about it, so every voice request would have answered 501 on a stack that looked complete.

That line is still only the server's opinion of its own config, and says nothing about whether the SFU came up.
The first real deployment of this stack hit exactly that gap: the server reported voice enabled while LiveKit crashlooped on DNS behind it, and nothing in CI would have noticed.
So the SFU is checked separately, and because a crashloop looks like a start too, the job also confirms the container is still running a moment after the start line appears rather than trusting the one log line.

The last check is the end-to-end property that matters: a token signed the way the server signs one is a token this SFU honours.
A key and secret pair that reached only one of the two services would pass every check above and fail on the first real call.
The converse is checked too, so that check cannot be passing on an SFU that would accept anything.

That validation call is plain HTTP on purpose, and it is the only correct choice there: it is a container-to-container call on a private compose network, to the port LiveKit serves unencrypted by design.
TLS is Caddy's job one hop further out, and Caddy is not running on the runner because it has neither a domain nor a certificate to serve.

## push-relay-contract

The server and the relay agree on the push envelope's wire framing (field names, types, the platform and kind vocabulary, the payload size limit) but live in separate repos and languages, so nothing else here would notice one side changing it.
This is the only job that checks out both and runs a server-produced request through the relay's real HTTP handler.
See `crates/slimm-server/tests/push_relay_contract_fixture.rs` and slim-m-relay's `internal/api/push_relay_contract_test.go`.

### No `token:` input on the relay checkout

The relay checkout deliberately passes no `token:` input.
An empty string is a provided value, not "unset", so it overrides checkout's own `default: ${{ github.token }}` and the step authenticates with a blank bearer instead of falling back to it, and GitHub responds 401 rather than serving the clone anonymously.
Leaving it unset lets the default apply, which is already sufficient to read a public repo.

### Three ways this job could go green having asserted nothing

Each of these is guarded explicitly, because all three fail silently.

A silently broken generation step, from a wrong env var name, a wrong path, or a future refactor of the fixture test that stops writing the file, must not fall through into the relay step quietly skipping while the job still goes green.
The workflow asserts the fixture file exists and is non-empty before using it.

A missing fixture at the relay step is a bug in this workflow, not a normal local-dev situation, so `SLIMM_PUSH_CONTRACT_FIXTURE_REQUIRED=1` makes the Go test fail loudly rather than take the `t.Skipf` it uses for an ordinary `go test ./...` run without a sibling slim-m checkout.

`go test -run` silently matching zero tests exits 0 with nothing asserted, which is the same failure shape as that skip.
Requiring the test's own `PASS` line means a typo'd pattern and a skip both fail the step.
`go test -v` prints the duration after the name (`--- PASS: X (0.00s)`), so anchoring the grep on the name alone would never match and the gate would fail every run regardless of the result.

## release

The full release and publish pipeline.

### How a release is cut

release-please maintains release PRs on push to `main`.
When a release PR is merged, that same push run cuts the GitHub Release plus tag and sets the per-package `release_created` outputs, which gate every downstream publish job.
A direct tag push (`server-v*` or `client-v*`) is also honored, so a release can be re-published without another release-please run.

The release-please job itself runs manifest mode against the existing `release-please-config.json` and `.release-please-manifest.json`, and only on main-branch pushes.
On a tag push it is a no-op so downstream jobs can still resolve it via `needs`.

Server (AGPL-3.0-only) and client (Apache-2.0) are versioned and released independently, each with its own tag and its own set of jobs.

Every job that pushes to GHCR, signs, attaches release assets, or touches TestFlight runs under a reviewer-gated GitHub Environment and requests only the permissions it needs.
Secrets are referenced by name only and never invented; jobs stay inert, showing a visible warning and producing no fake artifact, until the corresponding secrets and packaging inputs exist.

The workflow-level `permissions` is a minimal default that individual jobs widen to exactly what they require.
Concurrency never cancels an in-flight release run, because a half-published release is worse than a queued one.

### server-image and server-image-merge

`server-image` builds one single-arch image per architecture on a native runner (amd64 on `ubuntu-latest`, arm64 on `ubuntu-24.04-arm`), each pushed to GHCR by digest with an SBOM and max provenance.
There is no QEMU cross-compilation.
It needs no secrets beyond the automatic `GITHUB_TOKEN` (`packages: write` to push to GHCR), and no cosign key material is stored.

`server-image-merge` assembles the per-arch digests into one multi-arch manifest tag and cosign-signs it keylessly over OIDC.
It signs the manifest-list digest, which covers both arch images and every tag that resolves to it.

`latest` is the rolling tag deployments track for auto-updates, since Watchtower polls a mutable tag.
The version and sha tags stay alongside it, for pinning and for tracing an image back to its commit.

### server-binaries and server-release-assets

`server-binaries` produces static musl binaries for direct download, built per arch into artifacts and aggregated by `server-release-assets`.
Each arch builds its own musl target natively on a native runner, with no `cross` and no QEMU, the same approach the container image uses.

`server-release-assets` attaches a GPG-signable `SHA256SUMS` plus the raw binaries to the server GitHub Release, under a reviewer-gated environment.
`GPG_PRIVATE_KEY` (ASCII-armored private key) and `GPG_PASSPHRASE` are optional: the attach still works without them and only the `.asc` is skipped.

### linux-client

The job publishes `slim-m-client-<version>-linux-amd64.tar.gz` on every client release, gated on nothing.
It is the Flutter bundle as built, plus the licence and `packaging/linux/README.md`, under one top-level directory.
That one artifact serves both readers: it is the download for a user whose distribution has no package, and it is the `Source0` the rpm spec fetches from the release.
Naming follows the server binaries in this same workflow (`slimm-server-<version>-linux-<arch>`), so one release page does not call the same machine `amd64` in one asset and `x86_64` in another.

Packaging then gates per format, not on both at once: `packaging/flatpak/org.slimm.Client.yaml` enables the Flatpak step and `packaging/rpm/slim-m-client.spec` enables the rpm step, independently.
An earlier version required both, which would have held a working rpm behind a flatpak manifest nobody had written.
Each missing input still warns by name, and the tarball ships either way.

The rpm is built inside a `fedora:latest` container rather than on the runner, because the spec is written against Fedora's macros and dependency generators and Ubuntu's `rpm` has neither.
It builds from the tarball staged moments earlier in the same job, not from the URL in `Source0`, since that release asset does not exist yet at that point in the run.
The `copr` job below is the one that goes through the published URL.
Both stamp the tag's version over the spec's `Version:` line, so a spec that is behind in git cannot mislabel a release.

The flatpak step is still a skeleton; its manifest will need to reference the same bundle as its app source.

`GPG_PRIVATE_KEY` and `GPG_PASSPHRASE` are optional here too, for signing the checksums only.

The job installs `libsecret-1-dev` as a system build dependency.
`flutter_secure_storage` is a normal pub dependency of the platform package, used on iOS and Android (see `persistent_key_store.dart`), and pub has no per-target scoping that would keep its Linux plugin `flutter_secure_storage_linux` out of a Linux build's dependency graph.
That plugin's CMake config hard-requires `libsecret-1-dev` to even configure, regardless of whether the app ever calls into it on this platform.
Installing the one system package is simpler to maintain than splitting the platform package apart just to keep Linux out of that graph.

### copr

Submits the Fedora package to COPR at `nc1107/slim-m`, so `dnf copr enable` reaches a built and signed repository rather than a release page.
It runs in a `fedora:latest` container because `copr-cli`, `rpmbuild` and `spectool` are Fedora packages and installing them onto the Ubuntu runner is more work than using the distribution that ships them.

Two things make it inert rather than red.
It skips with a visible warning when `COPR_CONFIG` is unset, the same shape as the Android and iOS jobs, and it skips again when `packaging/rpm/slim-m-client.spec` does not exist, which is the same condition `linux-client` already gates its packaging steps on.
A submit that is attempted and fails is also only a warning: the `.rpm` is already attached to the release by then, so COPR being unreachable must not fail a release that has otherwise published everything.

`COPR_CONFIG` is the verbatim contents of `~/.config/copr`, the `[copr-cli]` block that <https://copr.fedorainfracloud.org/api/> generates.
It is a bearer credential for the whole COPR account, not just this project, and it expires: the token page states an expiry date and a build submitted after it fails with an authentication error rather than anything that names expiry.

The version reaches the spec through an `%app_version` macro appended to `~/.rpmmacros`, rather than a `--define` flag, because both `spectool` and `rpmbuild` read the macro file and the job needs the same value in both.
The `Version:` line is rewritten only when the spec hardcodes it; a spec that expands a macro there is left alone.

`spectool -g -R` downloads `Source0` into the SRPM before submitting.
That step is the whole reason this job exists in this shape: COPR builds in a mock buildroot with no network, so anything `Source0` points at has to already be inside the SRPM when it arrives.
It is also why the package repackages the release tarball instead of building from source, since a Flutter build resolves pub dependencies over the network and could never run there.

Operator-facing detail, including how to submit a build by hand, is in `packaging/fedora/README.md`.

### android-client

Builds the upload-signed apk and appbundle and attaches them to the client release.
It is inert until the signing secrets exist, and it verifies the signer is the upload key, since silently falling back to the debug keystore is the exact failure this job exists to close.

All three secrets must be present for the job to do real work:

- `ANDROID_UPLOAD_KEYSTORE_B64` - base64 of the upload keystore (`.jks`).
- `ANDROID_KEY_PROPERTIES` - the contents of `key.properties`.
- `ANDROID_GOOGLE_SERVICES_JSON` - the contents of `google-services.json`, which is gitignored; without it push is silently disabled.

`EXPECTED_SHA256` in the verify step is Play's registered upload certificate fingerprint.
It is public information, not a secret, and it is the only check that proves Play will accept the upload.
The apksigner output is captured to a file and echoed before matching, because the previous form assigned a grep pipeline and a miss aborted with no output at all.

Java is pinned to Temurin 21, the LTS the Android Gradle Plugin supports; local builds match.

Both the version and the tag are emitted by the resolve step: the tag names the release and the version feeds `--build-name`.
Emitting only the tag left `--build-name=` empty on every run before that was fixed.

### ios-testflight

Builds the signed ipa and uploads it to TestFlight, under a reviewer-gated environment.
It is intentionally inert until the signing and App Store Connect secrets exist, and warns and stops rather than faking an upload.

All six secrets must be present for the job to do real work:

- `APP_STORE_CONNECT_KEY_ID` - App Store Connect API key id.
- `APP_STORE_CONNECT_ISSUER_ID` - App Store Connect issuer id.
- `APP_STORE_CONNECT_PRIVATE_KEY` - the contents of the `.p8` API private key.
- `IOS_SIGNING_CERTIFICATE_P12` - base64 of the distribution certificate (`.p12`).
- `IOS_SIGNING_CERTIFICATE_PASSWORD` - the password for that `.p12`.
- `IOS_PROVISIONING_PROFILE` - base64 of the `.mobileprovision` profile.

The signing identity goes into a throwaway keychain rather than the login one.
The runner is ephemeral, and a dedicated keychain keeps the private key out of any shared default that later steps touch.

`security set-key-partition-list` is mandatory: without it, `codesign` prompts for permission and hangs a headless run.

xcodebuild finds a provisioning profile by its UUID under `~/Library/MobileDevice/Provisioning Profiles`, so the file has to be named for the UUID embedded in its own signed plist.

The job prints the identities visible to codesign before building.
A signing failure downstream is otherwise reported only as "no valid code signing certificates were found", which says nothing about whether the import worked.

### Build numbers and build names, on both mobile jobs

`--enforce-lockfile` on `flutter pub get` so a release build resolves exactly what the committed `pubspec.lock` pins, rather than whatever is newest today.

`--build-number` comes from the GitHub run number, not from pubspec.
Both stores reject a build number that has already been used, and App Store Connect does it asynchronously: altool uploads happily, the job goes green, and the build is rejected minutes later by email.
That is how the iPhone build sat on build 4 through four client tags while CI looked fine every time.
A run number is monotonic and cannot be forgotten, so a reused build number stops being possible rather than being something to remember.

`--build-name` comes from the tag, not from pubspec.
The pubspec version is a local-build default and has sat at 0.1.0 across every release, so without this a tester cannot tell one build from another and every TestFlight build reads 0.1.0 whatever was tagged.
