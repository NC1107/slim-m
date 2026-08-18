# CI and the release pipeline

Why the workflows in `.github/workflows/` are shaped the way they are.

A YAML file has no doc-comment mechanism, so a `#` block at the top of a workflow is the only thing it can carry, and this repo caps a plain comment elsewhere at one line.
Anything that needs more room than that lives here, and the workflow keeps a short note pointing at the section.
Each section below is named for its workflow file.

## Workflows at a glance

| Workflow | Runs on | What it gates |
| --- | --- | --- |
| `server-ci` | changes under `crates/`, `schema/openapi.yaml`, the Cargo files, `rust-toolchain.toml`, `docker/server.Dockerfile` | fmt, clippy, tests, release build, binary size budget |
| `client-ci` | changes under `client/`, or to `schema/openapi.yaml` | dart analyze and format in one job, every package's tests plus the web build in another, so a typo reports in about a minute rather than fourteen |
| `client-macos-ci` | changes under `client/packages/app/macos/`, `rtc/`, `platform/`, the pubspec files on pull requests; every push to `main` that touches `client/` | that the Dart and Swift compile against the macOS SDK. Compile-only, unsigned, and not a required check |
| `client-windows-ci` | changes under `client/` | that the native plugin graph links against the Windows SDK. Compile-only, and not a required check |
| `client-ios-ci` | changes under `client/packages/app/ios/`, `rtc/`, `platform/`, the pubspec files; every push to `main` | every `Runner` source file is registered in `project.pbxproj` (ubuntu, always), the iOS CallKit XCTest and extension-embeds-no-frameworks checks on macOS, and an unsigned Release-configuration device build when a native-relevant path changed |
| `schema-ci` | changes under `schema/`, `redocly.yaml` on pull requests; every push to `main` unconditionally | redocly lint, the additive-only oasdiff gate against a PR's base on pull requests, and the same gate against the immediate parent commit on every push to `main` (required for a release; see below) |
| `audio-ci` | changes under `assets/audio/` | the seven notification sounds rebuild to the bytes that are committed, and the family is level with itself |
| `hygiene` | every push and pull request | iOS purpose strings, the iOS broadcast extension is wired up, orientation is locked on phones only, no emoji in UI source, SPDX headers on Rust source, the file-size budget, the comment cap, and the `scripts/lib` unit tests, which include the two structural gates on `required_checks` |
| `advisory-watchdog` | a daily schedule, and by hand | nothing. It opens a deduplicated GitHub issue for a security advisory against a dependency and closes it once the tree is clean; the trigger `licenses` deliberately does not carry |
| `licenses` | changes to any dependency manifest or lockfile or to `deny.toml`; every push to `main` | every Rust crate's and every pub package's license is in the one allowlist |
| `perf` | changes under `crates/`, `perf/`, the Cargo files; plus published releases | benches compile on PRs, benches run on a release |
| `compose-smoke` | changes to the self-host stack, a weekly schedule, and by hand | `docker compose up` on a fresh box produces a working deployment |
| `e2e` | pull requests touching `client/`, `crates/`, the schema or the harness; every push to `main`; a nightly schedule; and by hand | the whole product through two real headless browsers; advisory, not required |
| `push-relay-contract` | changes to the server's push path, and by hand | a server-generated envelope through the relay repo's real HTTP handler |
| `verify-release-checks` | called by `release`, twice, once per component | that this exact commit's own CI completed and succeeded before any publish job runs, on both the release-please and the hand-pushed-tag paths |
| `copr-publish` | called by `main-builds` | the Fedora COPR snapshot submission, split out into its own file once `main-builds` hit the 500-line ceiling |
| `desktop-clients` | `client-v*` tag pushes, and by hand with a tag input | unsigned Windows and macOS tester archives, attached to the client's GitHub release. The two desktop platforms `release` does not package |
| `release` | pushes to `main`, and `server-v*` / `client-v*` tags | the whole publish pipeline |
| `release-tag-watchdog` | a 15-minute schedule, and by hand | every release-please manifest's version has a matching git tag, catching a release PR that merged with no tag ever following it |
| `red-streak-watchdog` | an hourly schedule, and by hand | opens a GitHub issue once `e2e` or `main-builds` has failed 3 consecutive completed runs on `main`, closes it once that workflow is green again; does not gate anything |
| `main-builds` | changes under `client/`, `crates/` or `packaging/` on every push to `main`, excluding a release commit's own files | continuous TestFlight, a Fedora COPR snapshot, an Android artifact, and `latest` on the live server image; never a version bump, changelog or GitHub Release |

## Keeping this table honest

Two gates in the `scripts/lib` unittest suite watch the table above, because CLAUDE.md sends readers here as the authoritative workflow list and a row that is wrong is worse than a row that is missing.

`scripts/check-ci-docs.py` enforces that every workflow has a row and every row names a real workflow file. It reads nothing inside the row, so for a long time the "Runs on" column could describe a trigger a workflow did not have, or omit one it did, with the gate green.

`scripts/lib/test_ci_docs_triggers.py` covers that next layer: a row for a workflow with a `schedule:` has to say so, and one with `workflow_dispatch:` has to admit it can be run by hand.
The rest of the column is prose and not mechanically checkable, but an omitted trigger kind is a factual gap rather than a wording choice.
Two rows had omitted `workflow_dispatch` before this existed.

It checks every workflow yields at least one trigger kind, per file rather than in aggregate: a workflow whose `on:` block drifts out of the parser's reach would otherwise be silently exempt while the other twenty keep the suite green.

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

The XCTest run is simulator only, so it needs no signing identity and no secrets: it compiles the Swift and runs XCTest, it does not produce a shippable build.
The signed device build stays in the release workflow.

### The registration and release-configuration checks, and why PR #292 needed both

Client 0.21.2 shipped a category on a private engine class from `ClipboardPasteBridge.m`, an undefined-symbol link error.
`ios unit tests` passed, because it links a Debug, simulator build; `build ipa` failed, because only a Release, device archive takes the same linking path the App Store review needs.
Separately, a new Swift file left out of `project.pbxproj`'s Sources build phase is skipped by `xcodebuild` with no error at all, so no test on either side can see it: not the native build (nothing failed) and not the Dart suite (it passes against a method channel that would have no handler).

Two checks close this, at very different costs.
`pbxproj-registration` is a grep over `project.pbxproj` with no Xcode involved, so it runs on `ubuntu-latest` unconditionally, ahead of the macOS jobs.
The `ios-unit-tests` job gained a second build step, `flutter build ios --release --no-codesign`: a real, unsigned, device-target Release build, which is what takes the same linking path `build ipa` does.
That step is narrowed to the `changes` job's `native` path filter rather than "main is never trusted on a filter alone": unlike the XCTest job, a linking failure can only come from a native source file, `project.pbxproj`, or a dependency version, since Dart code takes no part in native linking.
Both checks are in `verify-client-ci`'s `required_checks`, since each can fail with the other green.

It lives in `client-ios-ci.yml` rather than beside the Dart job because it is the expensive one by an order of magnitude: 14 minutes against 5, measured across recent runs, which made `client-ci` a median of 11 minutes when the Dart half finishes in a third of that.
A GitHub workflow cannot path-filter one job, so the split is what lets it be gated on the paths that can actually change its answer: the iOS project, the plugins carrying CallKit and WebRTC, and the dependency set, which is how a Dart-side change reaches an Xcode build.
Every push to `main` runs it whatever changed, so `main` is never trusted on a path filter alone.
CocoaPods is cached on the lockfiles, since rebuilding those pods is most of what the project-generation step spends its five minutes on.

`flutter build ios --simulator --no-codesign` runs first because xcodebuild needs the generated Flutter config and the plugin registrant to exist before the project will open, and only a Flutter build makes them.
`--no-codesign` keeps it to compiling, with no identity involved.

The simulator is chosen from what the runner actually has rather than by name.
A hardcoded `iPhone 16` broke the first time this ran, and it would break again silently every time GitHub rolls the image forward.

`schema/openapi.yaml` is in the path filter even though it is not Dart, for the same reason `server-ci` watches it: a client test reads it.
`packages/api`'s `schema_coverage_test.dart` fails when a route is documented with no `SlimmApi` call behind it, so a schema-only change can break this workflow while never triggering it.
That is not hypothetical - #675 documented `bulkDeleteMessages`, touched no `client/` file, and landed a red `api` package on main that no PR check had run.

## schema-ci

`oasdiff breaking` reports only changes that break existing clients: removed paths and fields, narrowed types, newly required properties, and similar.
Purely additive changes such as a new optional field or a new endpoint are not breaking and pass, which is what makes this gate additive-only by construction.

Two jobs run it, against two different bases, because one commit needs both.

`breaking-change-gate` runs on `pull_request` and diffs the PR's base against its head - the meaningful comparison for a reviewer, and the one that can catch a breaking change before it ever reaches `main`.
The PR's head commit is checked out explicitly rather than the default merge-ref checkout, so `HEAD:schema/openapi.yaml` is exactly the schema the PR proposes with no synthetic merge commit in between.
oasdiff also needs the base branch's schema content, but that checkout only fetched the PR head commit, so the workflow fetches just that one base commit, shallowly, by its exact SHA from the `pull_request` event payload, landing it in the local object database without cloning the base branch's history.
oasdiff then reads it straight out of git as `<base-sha>:schema/openapi.yaml`.

`breaking-change-gate-main` runs on every push to `main` instead, diffing `HEAD~1` against `HEAD`.
This is not redundant with the PR-time gate: `verify-release-checks.yml` (see below) polls check-runs on the exact commit a release verifies, a squash-merge mints a brand-new SHA that the PR-time gate's check-run was never attached to, and a release-please commit never touches `schema/**` at all - so `breaking-change-gate` structurally cannot ever appear on the commit a release actually checks, no matter how the required-checks list is written.
`breaking-change-gate-main` is what can: it is unconditioned on any path filter and runs on literally every push to `main`, trivially passing (an empty diff) on the overwhelming majority that never touch `schema/openapi.yaml` at all.
This relies on this repo's squash-merge-only convention (see "Contribution conventions" in `CLAUDE.md`): `HEAD~1` is exactly the one commit a merged PR added.
A direct multi-commit push to `main` bypassing that convention would only diff the last of them; not a concern under the convention this repo actually follows, and not worth the added complexity of walking further back for a case that should not happen.

### The one OpenAPI 3.0 `nullable` in the schema

`RegisterRequest.invite_code` in `schema/openapi.yaml` is written with the OpenAPI 3.0 `nullable` keyword, alone in a 3.1 document.
oasdiff cannot read a 3.1 `type: [x, "null"]` union and reports the conversion as the property losing nullability, which fails the additive-only gate, and redocly rejects carrying both forms at once.
It is a request property, so nothing is testable either way: the field is optional through `required` regardless, and the server takes an absent value and an explicit null identically.

## hygiene

### The e2e harness's own unit tests

`scripts/lib/test_*.py` covers the harness's scenario logic (the read-state and sync assertions, the settings assertions) against stubs, with no server and no browser.
`e2e.yml` runs the same discovery, but only on push to main, and only as an advisory check; this is the `pull_request` gate on it, so a regression in the harness itself fails a PR rather than a nightly run nobody is watching.

### iOS purpose strings

App Store review rejects a binary whose linked SDKs reference a sensitive API without a purpose string, and it does it asynchronously.
altool uploads, the job goes green, and the rejection arrives by email some minutes later.
This gate turns that into a red PR instead.

### The iOS broadcast extension is wired up

Every piece of the screen-share broadcast extension (the Xcode target, its App Group, its Info.plist entries, its embedding in the app bundle) fails silently at runtime when wrong: the button does nothing, or the broadcast starts and sends no frames.
This step checks the identifiers agree with each other across `project.pbxproj` and both Info.plists rather than merely that each file exists, since that is exactly how this shipped broken once already.

### Orientation is locked on phones only

Phones are locked to portrait and tablets are free to rotate, on both platforms, and the two halves fail in opposite directions if either is quietly edited.
This step reads the iOS orientation arrays, the two Android `bools.xml` overrides, and the Kotlin code that applies the lock, and fails if any of the four no longer agrees with the others.

### No emoji in UI source

Emoji are user content (reactions), never interface chrome; chrome uses Lucide icons.
The gate fails on any emoji codepoint in client source.
It matches text sources only and passes `--binary-files=without-match`, so a compiled artifact that happens to contain those bytes cannot trip it.

### SPDX headers on Rust source

Every file under `crates/` needs an `SPDX-License-Identifier` header on its first line; this step fails and names the file otherwise.
CLAUDE.md's own contribution rule says "a CI gate checks the Rust ones," and `find crates -name '*.rs'` is that scope exactly, not a gap - widening it to the Dart, Swift and Kotlin sources that also lack headers is a separate, smaller decision nobody has made yet.

### The file-size budget

`scripts/check-file-budget.sh` enforces the rule in `CLAUDE.md`: 300 lines soft, 500 lines hard.
It warns at 300 and fails at 500, because 300 is the review budget rather than a limit and failing on it would fail the repository as it stands.
When this was written 64 files were over 300 and 14 were over 500.

The check runs over hand-authored source only, from `git ls-files`, so nothing untracked or ignored is counted: `.rs`, `.dart`, `.py`, `.sh`, `.swift`, `.kt`, `.kts`, `.js`, `.sql`, `.yml`, `.yaml`, `.toml`, `.cc`, `.h`, `.gradle`.
Generated Dart (`.g.dart`, `.freezed.dart`, the protobuf suffixes), the committed `.sqlx/` cache and the vendored `node_modules/` are excluded, because their size is nobody's decision here.
Markdown is excluded too, deliberately: the budget is a code-review budget, and prose is not reviewed by the line.
Including it would put this file, `CLAUDE.md` and most of `docs/` over the hard limit on day one, which would make the gate noise rather than a gate.

The 14 files already past 500 are listed in `scripts/file-budget-allow.txt` with the line count they were listed at and a one-line reason.
That number is the point.
The gate treats it as that file's own ceiling, so a listed file may shrink and may not grow, and raising a number is a visible line in a diff somebody has to justify.
An entry whose file has dropped back under 500, or which no longer names a checked file, is an error rather than a silent no-op, so the list cannot rot the way a plain exemption list would.

Nothing in that list is a judgement that the file is acceptable.
The two worst are production code, not tests: `store/sessions.rs` at 815 lines carries tokens, refresh rotation, ws tickets and account deletion together, and `push.rs` at 600 carries envelope sealing, the relay client and fan-out triggering.
Splitting them is real work with real regression risk and does not belong in the change that introduces the gate.
`schema/openapi.yaml` and `release.yml` are the two that will most likely stay: one OpenAPI document split across `$ref` files would give `tests/openapi_contract.rs` two sources to reconcile, and the release workflow's ten publish jobs share release-please's outputs.

### The comment cap

`scripts/check-comment-cap.sh` enforces the other half of the same `CLAUDE.md` rule: a plain `//` or `#` comment never exceeds one line.
It ratchets rather than merely allows: a file may not gain a new run past its listed count, and the pre-existing ones are frozen at the count they were found at in `scripts/comment-cap-allow.txt`, the same shape as the file-size allowlist above.
Doc comments (`///`, `//!`, `/**`) are exempt everywhere, and a `#` block at the very top of a YAML, TOML or shell file is treated as that file's doc comment for the same reason those languages have no other doc-comment syntax.

## licenses

Two jobs, one policy.
`deny.toml` holds the allowlist; cargo-deny reads it directly for the Rust tree and `scripts/check-dart-licenses.py` reads the same `[licenses]` table for the Dart tree.
One file rather than two, because the failure this gate exists to catch is a copyleft dependency arriving quietly in the Apache-2.0 client, and two policies that can drift is how that arrives.

It is not part of `hygiene` because both halves need a toolchain.
`hygiene` is the seconds-long grep job that runs on every push with nothing installed, and a cargo metadata resolve plus a `flutter pub get` would turn that into minutes.
So it is path-gated on the manifests, the lockfiles and the policy, plus every push to `main` whatever changed.

### What is allowed, and what is not

Every entry in `allow` is permissive and imposes no source-disclosure obligation on either the AGPL server or the Apache-2.0 client (see `LICENSING.md`).
Nothing is listed speculatively: the list is exactly what the two trees resolve to today, so a new license of any kind stops the gate and gets a human decision.

Three package-level exceptions, each named one package at a time rather than allowing the license outright:

- `slimm-server` is allowed `AGPL-3.0-only`, since it is the server itself. Allowing AGPL across the board would let a third-party AGPL crate in unnoticed, which is the opposite of what this is for.
- `dbus` and `nm` are allowed `MPL-2.0`. MPL-2.0 is per-file copyleft: the obligation reaches modifications to those packages' own files and not the application that links them, so it is compatible with shipping an Apache-2.0 client. That is a decision rather than a default, which is why it is two named entries and not a line in `allow`; a new MPL dependency still stops the gate. Both are Linux desktop transitives reached through `connectivity_plus`.

Advisories and bans are deliberately not configured here, so this is `cargo deny check licenses` and not `check all`.
A CVE published upstream would turn every unrelated pull request red through no fault of its own, which is a different job wanting a different trigger; `docs/STRATEGY.md` names `cargo audit` and `osv-scanner` for it and neither is wired yet.

`-A license-exception-not-encountered` is passed because the allow list is shared: `dbus` and `nm` are pub packages, so cargo-deny correctly reports never having seen them, and that is not a finding.
`unused-allowed-license = "allow"` in the config is there for the same reason in the other direction.

### The Dart half, and why it reads license text

pub has no cargo-deny, and a pub package declares no license anywhere in its pubspec; pub.dev derives what it displays from the package's `LICENSE` file.
So the script parses `client/pubspec.lock`, finds each hosted package in the pub cache, and classifies the license text itself.

That means the job has to run a real `flutter pub get --enforce-lockfile` first, and it means two failure modes are checked explicitly rather than skipped:

- A package the classifier cannot identify is an error, not a pass. A gate that shrugs at what it cannot read is not a gate, and the fix is to look at the file and either widen the classifier or record what it is.
- A package missing from the cache is an error naming the count, so an empty or partial cache fails loudly instead of the run going green having checked nothing.

One trap in the classifier, found by running it rather than by reading it: MPL-2.0's own text names the GPL, the LGPL and the AGPL, in the clause defining a Secondary License.
Matching the GNU family anywhere in the file therefore read `dbus` and `nm` as AGPL-3.0-only, which was a wrong label on a correct-enough refusal, and would have been a wrong label on a wrongly permissive answer just as easily.
The GNU family is matched against the first 600 characters only, where a real GPL text carries its title.

Today it reads 157 packages: 124 BSD-3-Clause, 24 MIT, 5 Apache-2.0, 2 BSD-2-Clause and the 2 MPL-2.0 above.

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

## e2e

`scripts/e2e.sh` is the most comprehensive check in the repository, and until this workflow it ran nowhere.
`grep -rln e2e .github/workflows/` returned nothing, so it gated nothing and had been failing since the settings restructure in #142 with no signal at all, found only by running it by hand.
A gate nobody runs is not a gate, which is the whole reason this workflow exists.

It builds the release server binary from source, builds a real Flutter web bundle, and runs a LiveKit dev-mode SFU in Docker, all inside the one job.
Nothing here is pulled pre-built, other than the pinned third-party actions and the LiveKit image itself.
`E2E_REBUILD=1` is set explicitly so the web bundle is always built fresh from the checked-out commit.
A cached build silently screenshots stale code instead, which has cost a confused debugging cycle before (see `CLAUDE.md`).
Chrome is not installed by this workflow: `ubuntu-latest` ships Google Chrome already, and the harness's own prerequisite checks fail loudly and by name if a future runner image ever drops it.
The only Python dependency beyond the standard library is `websocket-client`, since the harness drives Chrome directly over the DevTools Protocol rather than through Selenium or a browser driver.

Not path-gated, on purpose, unlike every other workflow here: it runs on every push to `main` regardless of what changed.
It is the one check that exercises the client, the server and the schema together, and a change confined to any one of those areas can still break a scenario the narrower, path-gated gates never see.
It is also not run on pull requests at all: a full run is too slow and drives too much real infrastructure to pay for on every PR, and the faster per-area workflows already gate a PR on its own area.
A nightly schedule and `workflow_dispatch` cover the gap that leaves.
A slow drift, such as a renamed label or a restructured settings screen, is caught within a day instead of only whenever somebody happens to run the script by hand, and a person can still trigger a run on demand without waiting for either.

**It is advisory, not required, until it has proven itself.**
Browser automation can be flaky for reasons that have nothing to do with the change under test, and a red check nobody trusts teaches people to ignore CI rather than read it.
Nothing in this workflow blocks a merge or a release: `verify-release-checks.yml`'s required-check list (see the `release` section below) does not name it.
Promote it once real runs on `main` show it green and stable, which takes more than one run to judge given the class of flakiness a real browser and a real SFU can introduce; add its job to branch protection, and to `required_checks` in `verify-release-checks.yml` if it should also gate a release.

Screenshots (`E2E_SHOTS`, one per interesting moment, plus one at the point any scenario gives up) upload as the `e2e-evidence` artifact on every run, not only on failure, since a passing run's screenshots are still useful evidence.
The browser's own console log goes up beside each failure screenshot, and the server's log with them.
That is not padding: the first real run on a runner (30565517095) failed nine scenarios and the screenshots could show only that a channel list was empty, while what settled it was a pair of 404s nothing was capturing. See `docs/e2e.md`.

See `docs/e2e.md` for what the harness actually covers and what it does not.

### red-streak-watchdog closes the "advisory and nobody is watching" gap this section already names

`e2e` has been red for a day, then red for two days a second time, each time with a release shipping over the top of it and nothing anywhere saying so; see PRs #379 and #550 for the two incidents.
Neither happened because `e2e` gates anything - it does not, on purpose, per this section above - they happened because nothing was watching a check that fails loudly in its own terms but reaches nobody.

`red-streak-watchdog.yml` runs on an hourly schedule (plus `workflow_dispatch`) and asks `scripts/check-workflow-red-streak.sh` a plain question of `e2e`'s own run history on `main`: how many completed runs in a row, most recent first, have failed, treating a cancelled run as neither a failure nor a recovery since it never actually ran the harness (see `e2e.yml`'s own "queued, not cancelled" concurrency comment).
Three in a row is the threshold - one is ordinary flake in a job driving a real browser and a real SFU, and firing on it would make this exactly the kind of check people learn to ignore, the same reasoning `e2e.yml`'s own header already gives for staying advisory in the first place.
Replayed against the actual 2026-08-09 incident's run history, three in a row was reached about 1h20m after the regression started, not the two days it took a person to notice.

**The signal is a GitHub issue, not this workflow's own colour.** A cancelled-while-pending run or a required check reading `cancelled` as failure are both already-documented ways a workflow's own status silently misses a problem (see "A release can succeed and still ship no store build" in CLAUDE.md); failing this workflow's job would only add a second thing nobody is watching. `scripts/check-workflow-red-streak.sh` opens an issue, labelled and deduplicated so an hourly run cannot open a second one, once the streak crosses the threshold, and closes it automatically the next time `e2e` succeeds on `main`. The label is created on first use rather than assumed to exist, since nothing else in this repository needs it.

Pulled into a script for the same reason `check-release-tag-lag.sh` was: `scripts/lib/test_check_workflow_red_streak.py` drives it against a fixture run list (`E2E_RUNS_JSON`) and a faked `gh` on PATH, so the threshold and the dedup/close logic are both tested without a real red workflow. One fixture replays the real 2026-08-09 history up to its third failure and asserts the script would have fired; a second is a genuinely mixed history (one failure among real successes) rather than an all-failure fixture, since an all-failure fixture proves nothing about where the threshold actually falls.

No concurrency group, the same reasoning `release-tag-watchdog.yml`'s own header gives for having none: an unconditional `cancel-in-progress: true` over a cron interval is what made that workflow fail three times within an hour of shipping (a run slower than its own 15-minute interval gets cancelled by the next one, and a cancelled run never asks the question), and this job is read-only and idempotent, so two of it overlapping costs nothing worth guarding against.

**This does not promote `e2e` to a required check.** `verify-release-checks.yml`'s required-check lists are untouched, and `e2e` still does not run on pull requests. Whether to promote it is still the open question this section's own advisory-not-required paragraph leaves for the owner; this closes the separate problem of a red streak going unnoticed regardless of what the answer turns out to be.

It runs on pull requests as well, path-filtered to `client/`, `crates/`, `schema/openapi.yaml` and the harness itself, so a docs-only change pays nothing.

That reverses the workflow's original position, and the reversal is worth recording because the original reasoning was good and still turned out to be incomplete.
The argument was that e2e is too slow and heavy for a pull request, and that the faster per-area workflows already gate one.
What that missed is that none of those workflows drives the product: when #653 moved the canvas into voice channels and the harness kept driving a text channel, fourteen scenarios were red on every commit for two days while every per-area check stayed green.
Both fixes then had to be merged unvalidated, because nothing ran e2e until after a merge.

It stays advisory rather than required even so.
Surfacing a break while it is cheap to fix is worth a slow check; blocking a merge on browser automation that can be flaky for unrelated reasons is a separate decision, and one to take only once real runs show it stable.

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

The release-please job runs manifest mode twice, once per package, each against its own config and manifest file (`release-please-config.server.json` / `.release-please-manifest.server.json` for the server, the `.client.json` pair for the client), and only on main-branch pushes.
Splitting the manifest is what stops one package's release commit from conflicting the other's still-open standing PR: both used to read and write one shared `.release-please-manifest.json`, so merging either PR moved that file underneath the other, on every merge that did not also carry releasable commits for it. See PR #321 for the incident history.

### The release PR's own checks

Both `release-please-action` invocations take `token: ${{ secrets.RELEASE_PLEASE_TOKEN || secrets.GITHUB_TOKEN }}`, and which one is in play decides whether a release PR can ever go green.

A PR opened with `GITHUB_TOKEN` is authored by `app/github-actions`.
GitHub holds bot-triggered workflow runs at `action_required`, so `e2e`, `licenses` and `hygiene` never start on it, and the PR sits at `UNSTABLE` with only SonarCloud reporting, permanently.
It is not a failure and not a slow queue, and it looks identical from `gh pr checks` to the other reason a PR here shows few checks, which is a merge conflict.
Measured on 2026-08-18 over every `hygiene` run ever queued on a release-please branch: bot-triggered was held 13 of 13, owner-triggered ran 3 of 3, and the three that ran are the ones approved by hand.
The discriminator is `triggering_actor`, not the workflow, the branch or the event.

With `RELEASE_PLEASE_TOKEN` set to a fine-grained PAT, the PR is authored by the token's owner and its checks run like any other PR's.
The PAT needs `contents: read and write` and `pull requests: read and write` on this repository, and nothing else.
Set it with `gh secret set RELEASE_PLEASE_TOKEN` so the value never lands in a file or a shell history; rotating it is a re-run of that one command.

The fallback to `GITHUB_TOKEN` keeps releases working while the secret is absent, at the cost of that behaviour.
So an unset secret is a quiet degradation rather than a broken release, which is the right default for a self-hoster forking this repository, and the reason it is written as a fallback rather than required.
On a tag push both invocations are a no-op so downstream jobs can still resolve their outputs via `needs`.

Server (AGPL-3.0-only) and client (Apache-2.0) are versioned and released independently, each with its own tag and its own set of jobs.

### Gating publish on the commit's own CI

Every publish job additionally requires `verify-server-ci` or `verify-client-ci` (`verify-release-checks.yml`, called twice) to have succeeded, on both trigger paths.
Before this existed, the tag path published unconditionally: `git tag server-v9.9.9 <sha> && git push --tags` built, signed and shipped an image with fmt, clippy, `cargo test --all`, the openapi-vs-router contract test, the license gate and the hygiene gates never having run on that ref, straight to a production deployment that auto-updates from the moving `latest` tag.

workflow_run cannot close this gap.
It fires only when a named workflow completes for the event that triggered it, and none of `server-ci`, `client-ci`, `client-ios-ci`, `hygiene` or `licenses` trigger on a tag push at all, by design, so that a ref that already ran CI on `main` does not run it again.
A tag push therefore raises no `workflow_run` event for any of them, which rules out the one mechanism that otherwise looks like the obvious fit.

The gate resolves the caller's `ref` (a tag on the release-please path, `github.sha` on the tag-push path) to a commit SHA once, then polls `GET /repos/{owner}/{repo}/commits/{sha}/check-runs` for that SHA and requires each listed check-run name to show `status: completed` and `conclusion: success`, retrying for up to 70 minutes before failing on a timeout.
A check run is attached to the commit rather than to the event that produced it, so this answers both paths uniformly: the SHA a tag points at is normally already on `main` and already carries the check runs its original push or PR produced, so re-pushing a tag to the same SHA still finds them and still republishes, which is the documented re-publish capability above.
A required name **absent** from the response is treated the same as one that failed, never as a pass, so a commit that never went through CI at all (never pushed to `main`, never opened as a PR) times out and fails closed instead of silently succeeding on an empty result - unless something is still queued for that commit, in which case it keeps waiting past the grace period rather than giving up on a slow runner.
A `cancelled` check is pinned as a hard failure too, on purpose: see client-ios-ci.yml's own header on the concurrency group that used to cancel it on every push to `main`.

The polling loop itself is `scripts/verify-release-checks.sh`, not inlined in the workflow, so `scripts/lib/test_verify_release_checks.py` can drive it against a fake `gh`.
It shipped three separate incidents before anything tested it: a cancelled check read as success, the release-please path verified `github.sha` instead of the commit it actually released, and a tag was passed to an endpoint that only accepts a SHA.
All three are now regression tests, not just fixed code.

`verify-server-ci` requires `check` (server-ci), `hygiene`, `cargo dependency licenses` (licenses) and `breaking-change gate (additive-only, push to main)` (schema-ci).
`verify-client-ci` requires `analyze, format check`, `test and web build`, `linux desktop compiles` and `linux desktop shell smoke (Xvfb)` (all client-ci), `ios unit tests (callkit invariant)` and `ios sources are registered in project.pbxproj` (client-ios-ci), `hygiene`, `pub dependency licenses` (licenses) and the same schema-ci gate.

Those names are matched by exact string against check-run names, and nothing in the workflow graph connects the string to the jobs it names.
`scripts/lib/test_release_required_checks_exist.py` is what closes that: it fails a pull request when a `required_checks` entry names no job, so a rename is caught there rather than at release time on `main`. Its sibling `test_release_required_checks_schema_gate.py` checks the other half - that the entry named can structurally reach a release commit at all.
The two Linux jobs joined the list on 2026-08-11: a release ships a Linux tarball, rpm and flatpak from every `client-v*` tag, and until then a client release could cut with the Linux desktop build red - the exact class both jobs' own doc comments describe main going red on, only at release time with nothing failing loudly.
Neither is path-filtered on `main` (both run on every push there), so the same guarantee the iOS checks rely on - `main` is never trusted on a filter alone - already holds for them.
Those are exact check-run names (a job's `name:`, or its id when a job sets none), matched literally; renaming one of those jobs without updating the matching `required_checks` string silently reopens the gap this closes, since the renamed check is simply absent and the gate times out and fails rather than warns.

~~`schema-ci` is not required: `tests/openapi_contract.rs` already runs inside `server-ci`'s `cargo test --all`, and `schema-ci`'s own job is a redocly lint of the document's syntax, not part of what either release actually ships.~~
Wrong, and corrected once checked rather than assumed: `tests/openapi_contract.rs` gates the route surface - method and path - against the router, but never the shape of a response body, which is exactly what a breaking `oasdiff` change (a removed field, a narrowed type, a newly required property) reshapes.
Every already-installed client, on a self-host that auto-updates from `latest` or a phone on its own store-review schedule, is trusting that the wire only ever grows.
Nothing enforced that at the release gate before this: `breaking-change-gate`, the job that actually checks additive-only-ness, ran on pull requests alone, which protects a reviewed PR but not a release cut from whatever is on `main` regardless of how it got there - and branch protection requiring it on `main` is an owner-only repository setting, not something this gate can lean on.
`breaking-change-gate-main` (schema-ci) is what closes that: see its own section above for why the PR-time job could never be the one `required_checks` points at.

Every job that pushes to GHCR, signs, attaches release assets, or touches TestFlight runs under a reviewer-gated GitHub Environment and requests only the permissions it needs.
Secrets are referenced by name only and never invented; jobs stay inert, showing a visible warning and producing no fake artifact, until the corresponding secrets and packaging inputs exist.

The workflow-level `permissions` is a minimal default that individual jobs widen to exactly what they require.

### A queued run is not an in-flight run

`cancel-in-progress: false` protects a run that has already started; it says nothing about one still queued.
GitHub allows at most one pending run per concurrency group, and when a newer run is queued behind an already-pending one, the older pending run is cancelled outright - a different rule from `cancel-in-progress`, and one that flag cannot reach.
The group used to be keyed on `github.ref`, which is identical for every push to `main`, so two merges landing within one release run's runtime (roughly ten minutes end to end) put the second push's run in exactly that position.

This happened for real on 2026-08-06.
Run `31083287291` (the server 0.33.1 release commit) was in progress from 08:02:48.
Run `31083316052` (the client 0.32.1 release commit, pushed 26 seconds later) queued pending behind it.
A third, unrelated push (`c15e82f`, a canvas fix) landed at 08:13:40, while the server run was still going, and that new run replaced the pending client run in the group - `31083316052` shows `cancelled` with zero jobs ever started, confirmed against the real run history via `gh api repos/.../actions/runs/<id>/jobs`, which returns an empty job list for it.
Had the third push not arrived, main would have been left with a merged release PR, a bumped manifest, a changelog commit, no tag, and no store build, with nothing anywhere saying so - the same failure shape as "A release can succeed and still ship no store build" above, one layer deeper: there the required check itself was cancelled and read as a failure; here the *release run* is cancelled before any check can even run, and nothing polls for a run that never happened.
The only reason client 0.32.1 shipped that night is that the third push's own release-please invocation, running to completion at 08:13:40-08:14:36, found the already-merged-but-untagged client release PR and cut `client-v0.32.1` from it - confirmed by that tag pointing at the release commit's own SHA, not the third push's.

**The fix is keying the concurrency group on the commit, `release-${{ github.sha }}`, rather than the ref.**
Every push produces a distinct SHA, so two different commits' runs are never in the same group and neither can ever be left pending behind the other; each runs to completion independently, which is what actually guarantees a queued run is never silently dropped - not a narrower `cancel-in-progress` condition, which only ever governs a run already in progress.
This was checked against what serialization by ref was actually protecting, rather than assumed to be free: two release-please invocations running concurrently each touch only their own package's config and manifest file (see the manifest-split entry above), so a client run and a server run were already independent; and two *ordinary* pushes (no releasable commits) running their release-please refresh of a standing PR concurrently, rather than queued one after another, trades a rare git-ref race for never dropping a push's refresh entirely - a race there surfaces as one release-please job step failing visibly, which the standing-PR-conflict pattern documented above already establishes self-heals on the next push, where the previous behavior's silent full-run cancellation did not surface anywhere at all.
A job-level concurrency group scoped to just the `release-please` job, rather than the whole run, was considered and rejected: since every other job in this workflow transitively depends on `release-please`'s outputs, a cancelled-while-pending `release-please` job would starve the same downstream jobs a cancelled-while-pending *run* does today, reproducing the identical failure at job granularity rather than closing it.
`cancel-in-progress: false` is kept, now only relevant to the SHA appearing twice in the group (a re-triggered run against the same commit), which release-please's own tag creation cannot cause here: it creates the tag through the default `GITHUB_TOKEN`, which GitHub's own anti-recursion rule excludes from raising a new `push` event, so a release-please-cut tag does not re-trigger this workflow at that SHA either.

**`schema-ci.yml` had the identical hole, unrelated to this incident and found only by checking every other release-adjacent workflow for the same shape rather than assuming this was the only file with it.**
Its `breaking-change-gate-main` job is required by both `verify-server-ci` and `verify-client-ci` and runs on every push to `main`, but the workflow's `concurrency` block was `cancel-in-progress: true` unconditionally - the exact bug "A release can succeed and still ship no store build" above already fixed on `client-ci`, `client-ios-ci`, `hygiene` and `licenses`, left unapplied on the one workflow added after that fix landed.
It now carries the same `cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}` condition those four already use.

**Superseded on 2026-08-11 by the stronger fix `release.yml` itself already used: all six required-check workflows (`hygiene`, `server-ci`, `client-ci`, `client-ios-ci`, `licenses`, `schema-ci`) now key their concurrency group per commit on `main`** (`group: <name>-${{ github.ref == 'refs/heads/main' && github.sha || github.ref }}`), keeping the ref-keyed group with cancellation on PR branches.
The conditional `cancel-in-progress` closed only the cancelled-while-running mechanism; a run still *queued* behind a pending one in the same ref-keyed group was still replaced outright, the separate rule the release.yml incident above proved `cancel-in-progress` cannot reach.
During a merge burst that left required checks silently missing on the middle commit, and `verify-release-checks` treats an absent required check the same as a failed one, so a release cut from that commit times out and fails 70 minutes later with nothing naming the cause.
Per-commit groups on `main` mean distinct pushes are never in one group, so no push's checks can be dropped by a newer push; the cost is concurrent runs during a burst, which these workflows tolerate by design (every job is read-only against the repo).
The other unconditionally-`true` workflows (`compose-smoke`, `audio-ci`, `push-relay-contract`, `perf`, `e2e`) were checked too and are not required checks in either `required_checks` string above, so a cancellation there cannot block a release the way `schema-ci`'s could; `main-builds.yml`'s own `cancel-in-progress: true` is unrelated to this release pipeline entirely and is documented as deliberate in its own section below.

**Proven versus reasoned, stated plainly.** The 2026-08-06 sequence above (run IDs, timestamps, an empty job list, the tag's own commit) is read from the real run history through `gh`, not inferred. That a SHA-keyed group can never produce a pending run is a property of the group key having no collisions across distinct pushes, which is git's own guarantee rather than something this repo can test against a real two-workflow-runs-racing GitHub instance; the git-ref-race trade for an ordinary push's release-please refresh is reasoned from how release-please's own standing-PR mechanism is documented to behave and from this repository's own recorded experience of it self-healing, not measured against a live race.
See PR #250 ("A release can succeed and still ship no store build") for the fuller incident record and the earlier variant of this bug.

### release-tag-watchdog closes the detection gap the fix alone leaves open

The SHA-keyed group stops a run from being silently cancelled, but nothing before this watched for the state that cancellation already produced once: a release-please manifest bumped to a new version, meaning its release PR merged, with no tag ever following it.
A push-triggered check cannot close this on its own, because the push that should have cut the tag is the same one that did not - there is no later event to hang a check on.
`release-tag-watchdog.yml` runs on a 15-minute schedule instead (plus `workflow_dispatch`) and asks a plain question of git history: for each package, does the current manifest version have a matching `<component>-v<version>` tag, and if not, how long has the manifest read that version?
`scripts/check-release-tag-lag.sh` does the check itself, pulled out so `scripts/lib/test_check_release_tag_lag.py` can drive it against a real temp git repo rather than the live one; a missing tag inside a 15-minute grace window is normal (the same run that merges a release PR usually tags it within its own run) and a missing tag past it is reported with `::error::`, naming the tag, the version, and how long it has been missing.

### server-image and server-image-merge

`server-image` builds one single-arch image per architecture on a native runner (amd64 on `ubuntu-latest`, arm64 on `ubuntu-24.04-arm`), each pushed to GHCR by digest with an SBOM and max provenance.
There is no QEMU cross-compilation.
It needs no secrets beyond the automatic `GITHUB_TOKEN` (`packages: write` to push to GHCR), and no cosign key material is stored.

`server-image-merge` assembles the per-arch digests into one multi-arch manifest tag and cosign-signs it keylessly over OIDC.
It signs the manifest-list digest, which covers both arch images and every tag that resolves to it.

`latest` is the rolling tag deployments track for auto-updates, since Watchtower polls a mutable tag.
The version and sha tags stay alongside it, for pinning and for tracing an image back to its commit.

`server-image-merge` moves `latest` only when the version it is about to publish is the newest one GHCR has ever seen for this image, compared with `sort -V` against every semver-shaped tag the registry already lists (`scripts/decide-latest-tag.sh`).
Re-pushing an old `server-v*` tag (the documented re-publish capability above) still builds, signs and republishes that version's own tag, but `latest` is left pointing at whatever is genuinely newest, with a `::warning::` annotation naming what was skipped and why.
A tag listing GitHub cannot read (a rate limit, a permissions gap) fails the same way, closed: the step answers `false` and warns by name, rather than treating "could not tell" as "nothing published yet".
This protects only tags cut at a commit that already contains this script: GitHub runs the workflow and the scripts it calls from the pushed ref, so a `server-v*` tag pointing at an older commit (every one that exists through 0.18.5) still republishes unconditionally, moving `latest` exactly as before this existed.
Closing that needs something outside this file: a tag protection ruleset, or GHCR's own immutable-tag setting.
Without this, republishing a newer-than-nothing-else tag would silently roll every auto-updating deployment backwards to it.

### server-binaries and server-release-assets

`server-binaries` produces static musl binaries for direct download, built per arch into artifacts and aggregated by `server-release-assets`.
Each arch builds its own musl target natively on a native runner, with no `cross` and no QEMU, the same approach the container image uses.
It builds with `--locked`, the same as the container image and every other server build in this workflow, so the raw binary someone downloads is built from exactly what `Cargo.lock` pins.

`server-release-assets` attaches a GPG-signable `SHA256SUMS` plus the raw binaries to the server GitHub Release, under a reviewer-gated environment.
`GPG_PRIVATE_KEY` (ASCII-armored private key) and `GPG_PASSPHRASE` are optional: the attach still works without them and only the `.asc` is skipped.

### linux-client

The job publishes `slim-m-client-<version>-linux-amd64.tar.gz` on every client release, gated on nothing.
It is the Flutter bundle as built, plus the licence and `packaging/linux/README.md`, under one top-level directory.
It resolves with `dart pub get --enforce-lockfile`, the same as the Android and iOS builds, so this download and the tarball the rpm and Flatpak jobs both build from are resolved from exactly what `pubspec.lock` pins.
That one artifact serves both readers: it is the download for a user whose distribution has no package, and it is the `Source0` the rpm spec fetches from the release.
Naming follows the server binaries in this same workflow (`slimm-server-<version>-linux-<arch>`), so one release page does not call the same machine `amd64` in one asset and `x86_64` in another.

Packaging then gates per format, not on both at once: `packaging/flatpak/top.npcserver.slimm.yaml` enables the Flatpak step and `packaging/rpm/slim-m-client.spec` enables the rpm step, independently.
An earlier version required both, which would have held a working rpm behind a flatpak manifest nobody had written.
Each missing input still warns by name, and the tarball ships either way.
The flatpak step also carries `continue-on-error: true`, unlike the rpm step: it has one real build behind it rather than the rpm's dozens of releases, so a bad first run must not be able to take the tarball or rpm down with it; see `packaging/flatpak/README.md`.

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

All eight secrets must be present for the job to do real work.
The list said six and named six until 2026-08-11, having never been updated when the broadcast extension gained a profile of its own:

- `APP_STORE_CONNECT_KEY_ID` - App Store Connect API key id.
- `APP_STORE_CONNECT_ISSUER_ID` - App Store Connect issuer id.
- `APP_STORE_CONNECT_PRIVATE_KEY` - the contents of the `.p8` API private key.
- `IOS_SIGNING_CERTIFICATE_P12` - base64 of the distribution certificate (`.p12`).
- `IOS_SIGNING_CERTIFICATE_PASSWORD` - the password for that `.p12`.
- `IOS_PROVISIONING_PROFILE` - base64 of the app's own `.mobileprovision` profile.
- `IOS_BROADCAST_PROVISIONING_PROFILE` - the same for the broadcast upload extension.
- `IOS_NSE_PROVISIONING_PROFILE` - the same for the notification service extension.

The app and both extensions are separately signed bundles, so each needs its own profile.
A missing one fails the export naming only that bundle id, which sends you looking at the wrong thing, so the gate checks all three before the build rather than at export time.

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

## client-macos-ci and client-windows-ci

Both are compile-only, both are deliberately not required checks, and both exist to catch a native break early rather than to prove the app works.

`client-macos-ci` builds `client/packages/app/macos/`, which is still a fresh `flutter create` scaffold with no signing identity, no notarization credential and no Apple Developer team behind it.
It builds `--debug` on this project's SPM-only plugin tree with no CocoaPods step, exactly as `client-ios-ci` does, which produces a local "Sign to Run Locally" binary needing no Apple account.
`docs/os_backlog/macos_backlog.md` holds what a distributable build still needs.

`client-windows-ci` is the first CI job that has ever built a Windows target here.
A green run proves the native plugin graph links; it does not prove the app runs, looks right, or that the tray and window-shell behaviour decision 0012 designed works on a real desktop.
Read `docs/os_backlog/windows_backlog.md` before promoting it to a required check or building anything on top of a green run.

## advisory-watchdog

`licenses` runs `cargo deny check licenses` and deliberately not `check all`, because a CVE published upstream would turn every unrelated pull request red through no fault of its own.
That reasoning names a different trigger as the answer, and this is it.

It gates nothing, and it does not report by its own colour: a scheduled workflow that only fails itself is a red tab nobody opens, which is the failure `red-streak-watchdog` already exists to correct.
It opens a deduplicated GitHub issue instead, and closes it once the tree is clean again.

## verify-release-checks

Called twice from `release`, once per component, so every publish job - a GHCR push, a cosign signature, a GitHub Release asset, a Play or TestFlight upload - requires this exact commit's own CI to have completed and succeeded first.

Before it existed, the tag path published unconditionally with no test workflow having run on that ref at all, straight into a deployment that auto-updates from the moving `latest` tag.

`workflow_run` cannot do this job: it fires only when a named workflow completes for the event that triggered it, and none of `server-ci`, `client-ci`, `client-ios-ci`, `hygiene` or `licenses` trigger on a tag push, deliberately, to avoid re-running CI on a ref that already ran it on `main`.

The `ref` input carries the sharp edge.
It defaults to `github.sha`, which is right for the tag-push path, but the release-please path must pass the created tag instead: release-please acts on the repository's current state while `github.sha` is whatever commit started the run, and the two diverge whenever a release merge lands while an earlier run is still going.
Verifying `github.sha` then waits on a check a path filter correctly skipped, times out, and skips every publish job behind it, which is what happened to server 0.23.0 on 2026-08-01.

## copr-publish

The Fedora COPR snapshot submission `main-builds` calls, pulled into its own file once that workflow reached the 500-line hard ceiling.

A reusable workflow rather than a composite action, because it needs its own container image (`fedora:44`), which a composite action cannot declare.

## desktop-clients

The two desktop platforms `release` does not package: iOS goes through TestFlight, Android attaches an apk and aab, and `linux-client` ships a tarball, an rpm and a flatpak, all from `release` itself.
This fills the gap with unsigned archives good enough to hand a tester, without touching `release`'s gated publish jobs.

Unsigned is a stated trade rather than an oversight.
Windows has no signing certificate anywhere in this project, so SmartScreen shows "unrecognized app" and the tester clicks through.
The macOS app is ad-hoc signed by the build itself, so Gatekeeper quarantines a downloaded copy and a tester opens it with right-click Open, or strips the attribute with `xattr -d com.apple.quarantine`.

Both jobs declare `environment: release`, matching every asset-publishing job in `release`.
They are tag-triggered, so unlike `main-builds` they should sit behind a reviewer gate if one is ever added; `main-builds` documents its own opt-out for the opposite reason, that a continuous build must not block on review.

## main-builds

The owner's own framing: "every time I go to main, I should be able to test on all devices that have changes... if I change the way voice canvas works and we take a PR to main, in 20 minutes or so I should automatically have an iOS release and Fedora PC should have the update also, with no extra touching involved."
This is the workflow that answers that, deliberately kept out of `release.yml`: that workflow's whole shape keys off release-please outputs and tag refs, and mixing an untagged path into it would make both harder to reason about.
Nothing here is versioned, changelogged, tagged or attached to a GitHub Release; that stays `release`'s job, triggered the same way it always has been by merging a release PR.
On a client merge, iOS reaches TestFlight and the owner's Fedora desktop gets a new build through the same COPR project `dnf upgrade` already polls; on a server merge, the live instance updates on its own, because `latest` moves.
A tagged release still supersedes all of this: it wins over any COPR snapshot of the same version (see the versioning section below), and it alone attaches signed assets to the GitHub release.

### What triggers it, and the one filter step that replaces two workflows

A single `on.push.paths` list cannot tell a client-only merge from a server-only one, so the trigger is deliberately wide (`client/**` or `crates/**`, minus a release commit's own `client/CHANGELOG.md` and `client/pubspec.yaml`) and a `changes` job built on `dorny/paths-filter` narrows that into the two booleans (`client`, `server`) every downstream job gates on.
The brief allowed splitting this into two workflows with their own top-level `paths` instead; one workflow with one filter step was chosen because it keeps the concurrency group, the header, and this section in one place, and because the filter step is one checkout rather than two.

The two client exclusions are load-bearing.
A release-please release commit for the client touches exactly `.release-please-manifest.client.json`, `client/CHANGELOG.md` and `client/pubspec.yaml` (verified against the actual `chore(main): release client 0.16.0` commit, back when the manifest was still the single shared file; the split manifest changed only which root-level file name that first one is).
Without the exclusions, that commit would also match `client/**`, and this workflow would rebuild and re-upload the exact commit `release.yml` just shipped to TestFlight and Play, under the same version, racing a second altool upload against the first.
No equivalent exclusion exists for the server side: a server release-please commit touches `crates/slimm-server/Cargo.toml` and `crates/slimm-server/CHANGELOG.md`, both under `crates/**`, so it still re-triggers `server-image` here.
That is accepted rather than worked around: excluding `Cargo.toml` from the trigger would also hide a real dependency-bump PR that happens to touch only that file, and there is no path-only way to tell the two apart.
The redundant build pushes the same `latest` the release itself would have pushed moments earlier for the same commit, so nothing wrong reaches production; it is simply a build that did not need to happen.

### What each side does

The client side reuses `release.yml`'s `ios-testflight`, `android-client` and `linux-client` steps verbatim where the two paths overlap: the throwaway keychain and `set-key-partition-list` for iOS, the upload-key signer verification for Android, the Fedora container for the rpm build.
It differs because there is no tagged release to publish against: `softprops/action-gh-release` has nothing to attach to on an untagged push, so the Android apk and aab go up as `actions/upload-artifact` run artifacts instead (there is no Android device to test the push path here, and the Play upload stays manual regardless, so an artifact is all this path is for).
The Linux side goes further than an artifact: it lands on the owner's actual Fedora machine, through COPR, covered in its own section below.
And the version name passed to `--build-name` is read directly out of `client/pubspec.yaml` (the file release-please itself writes, and the exact value this workflow's own trigger excludes from re-triggering it) rather than out of a release-please output or a tag, since neither exists here; it therefore repeats across every continuous build until the next real release moves it, which is fine, because uniqueness is per version-and-build, not per version alone.
`--build-number` still comes from `github.run_number`, exactly as `release.yml` uses its own, for the same reason: both stores reject a reused build number for a version.
Worth naming rather than assuming away: `release.yml` and `main-builds.yml` are two different workflow files, so each has its own independent `run_number` counter, and nothing here proves those two counters can never land on the same integer while a version briefly overlaps between a continuous build and the release that follows it.
No such collision has been observed, and `release.yml` runs on every push to `main` regardless of path while this workflow only runs on a subset of those pushes, which keeps its counter behind; if that ever stops holding, the fix is to derive the build number from something workflow-independent, such as a count of commits.

The server side pushes one native `linux/amd64` image to GHCR, tagged `sha-<commit>`, `main` and `latest`, with no arm64 build, no digest-then-merge manifest assembly and no cosign signing.
amd64 only because nothing consumes an arm64 image from this path: the owner's live instance (`CLAUDE.md`'s "Running deployment" section) is an amd64 Ubuntu Docker host, and a released version still gets the full signed multi-arch manifest `release.yml` builds.
Moving `latest` here is continuous deployment in the plain sense of the term: Watchtower on the live instance polls that tag, so a server merge reaches production within one build with nobody deploying it by hand, and a bad merge reaches it exactly as fast.
That is the trade the owner asked for explicitly, not a gap: fast iteration on the one host that matters to him, at the cost of no gate between a merge and production.

### Fedora, COPR, and the two problems a snapshot build has that a release does not

`packaging/rpm/slim-m-client.spec`'s `Source0` points at a GitHub *release* asset (`.../releases/download/client-v%{version}/slim-m-client-%{version}-linux-amd64.tar.gz`), and the release path's `copr` job fetches it with `spectool -g -R` because COPR's mock buildroot has no network and needs the tarball inside the SRPM before it submits.
An untagged main push has no such release, so `spectool` would 404 on every single continuous build.
The fix is not to create a release to satisfy it: `linux-client` already builds the identical tarball for its own rpm, uploads it as the `slim-m-client-tarball` artifact, and the `copr` job downloads that artifact and copies it into `~/rpmbuild/SOURCES/` under the exact filename `Source0` names, then calls `rpmbuild -bs` directly with no `spectool` step at all.
The release path's own `spectool` call is untouched; this is a second, parallel way of populating `SOURCES/`, not a change to the first.

The spec is committed at `Version: 0.4.0` / `Release: 1%{?dist}`, and the release job already rewrites `Version` to the tag's version on its own copy of the spec, never on the one in git.
A continuous build does the same version rewrite (to the client's current tracked version, read out of `client/pubspec.yaml`, the same value the mobile builds use), but it also has to rewrite `Release`, or every snapshot of one version would collide with the committed `1%{?dist}` and with each other.
It is set to `0.${{ github.run_number }}%{?dist}`.
RPM's version comparison splits `Release` into alphanumeric segments and compares them one at a time, so `0.<n>` and `1` compare on their first segment, `0` against `1`, and `0` always loses.
That means every snapshot of a given version sorts below the real tagged release of that same version, however high its own run number climbs, so cutting an actual release always supersedes whatever snapshots came before it on `dnf upgrade`, while snapshots still sort in increasing order among themselves because `run_number` only grows.
Neither the committed spec's `Release:` line nor the release path's own behaviour is touched; both rewrites happen only on the build-time copy under `~/rpmbuild/SPECS/`.

### Secrets, gating, and the environments it deliberately does not use

Every job that needs a secret checks for it first and warns rather than fails when it is absent, the identical shape `release.yml` uses for its Android, iOS and COPR jobs: a fork or a repo missing a credential gets a visible warning and a skipped step, never a red required check.
`release.yml`'s equivalent jobs declare `environment: release` or `environment: testflight`; this workflow's jobs deliberately do not.
Checked directly against the repository (`gh secret list`, `gh api repos/.../environments`): every secret these jobs read is a repository-level secret, not an environment-level one, and both environments currently carry no protection rules, so omitting the environment name changes nothing about what a job can read today.
It is still the right default for this workflow rather than an oversight: an owner open item already on record is adding reviewer protection to those two environments for real releases, and if that lands later, a job that names the same environment here would suddenly require a manual approval on every ordinary merge, which defeats the entire point of a fast, unattended path.

### Concurrency, and why it is the opposite of `release.yml`

`release.yml` sets `cancel-in-progress: false`, because a half-published release is worse than a queued one.
This workflow sets it `true`, because a continuous build carries no such asymmetry: a newer commit's build simply supersedes an older one's, so cancelling the older run in favour of the newer one loses nothing worth keeping.
