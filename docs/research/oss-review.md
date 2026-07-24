# Open Source Strategy and Repository Structure: Adversarial Review

Status: pre-implementation critique of `docs/research/oss.md`.
Scope: the same axes the report itself covers, plus consistency against the brief and against the sibling reports it should have been reconciled with (`networking-relay.md`, `security.md`, `backend.md`), plus direct verification against the reference repositories the report cites (`decentralized-chat-app` / echo-messenger, `check-in-relay`).
Severity is reserved for "critical" only where the finding would force a redesign before implementation starts.

## Summary

`oss.md` is written mostly as a licensing and governance document, and on those two axes it is careful and well argued: the AGPL-for-services, Apache-2.0-for-client split is sound, and replacing PolyForm Noncommercial is correctly identified as a real mistake to fix, not a style preference.
Where the report is weaker is repository layout, specifically the two-repo split between the core monorepo and the relay.
Its central justification, that the relay "should change rarely once APNs/FCM integration is stable," is contradicted by `networking-relay.md`, a sibling report in the same folder that the specialist had access to and that commits the relay to a direct APNs provider path, a new platform-routed wire format, and a worker pool, none of which exist in `check-in-relay` today.
The report also leans on the reference repository, echo-messenger, for more proof than it actually provides: echo's Flutter client is a single Dart package with no Melos split, so the "compiler-checked package boundary" guardrail the report proposes for Dart has no working precedent in the codebase it cites, and the mixed-license monorepo the report recommends (AGPL server, Apache-2.0 shared code, one repo) has no analog in echo at all, which is single-licensed throughout.
Finally, the report treats the relay's separation as free of the coordination problem it identifies for client and server, without noticing that the push envelope crossing the server-relay boundary is exactly the kind of shared contract its own client/server argument warns about.

## Major findings

### 1. The relay's "should change rarely" premise is contradicted by a sibling report the specialist had access to

Target: `oss.md` section 1, "a different release cadence since it should change rarely once APNs/FCM integration is stable," used to justify a separate repository for the relay.

Weakness: `networking-relay.md`, written before `oss.md` in the same `docs/research/` folder, does not treat APNs integration as stable.
It commits to adding a new `internal/apns` package "mirroring `internal/fcm`'s shape," a `platform` field routing every send, ES256 JWT credential rotation, and a bounded worker pool to replace check-in-relay's "fully serial one-token-at-a-time send loop."
None of this exists in `check-in-relay` as it stands today; it is new development scoped to happen alongside the initial server build, not after some settled baseline.
The premise that the relay is a slow-moving, already-stable dependency is not true at launch, which is exactly when the cost of cross-repo choreography is highest.

Failure mode: initial development proceeds under the two-repo plan, and the relay's wire format (the `kind`, `platform`, and `ciphertext` fields `networking-relay.md` specifies) needs to change two or three times as the APNs path and the server's push-encryption scheme get built out together.
Each change requires a coordinated PR in a second repository with its own review and release cycle, for a component the report assumed would not need that kind of coordination for years.

Resolution: revise the release-cadence rationale to reflect the real one, or track relay and server versions together (a compatibility matrix or synchronized tags) for the period during which APNs support and the push envelope are still being built, even while keeping the repos physically separate.

### 2. The server-relay push envelope is an atomic-change contract the two-repo split does not account for

Target: `oss.md` section 1's repository-layout rationale, which argues client and server must stay together because "the WebSocket wire protocol is the one artifact both sides must change atomically," but applies no equivalent scrutiny to the relay boundary.

Weakness: `networking-relay.md` describes a real shared contract between the home server and the relay: `/v1/send` accepts `{token, platform, kind, ciphertext, collapseId, priority}`, where `ciphertext` is "the home server's encryption of the real notification content to the device's push public key."
That is a format both the Rust server (which produces it) and the Go relay (which forwards it) must agree on, change together, and keep backward compatible, the same shape of problem the report uses to justify keeping client and server in one repository.
`oss.md` never applies its own reasoning to this second protocol boundary.

Failure mode: the server team changes the push-envelope schema (for example, adding a new `kind` for a feature like typing indicators over push, or changing how `collapseId` is derived) without a matching relay-repo PR landing first, and self-hosted servers running the new server version send malformed or misrouted pushes to the one shared production relay, silently breaking notification delivery for every self-hosted install running that version until the relay is separately updated.

Resolution: name the push envelope as a second cross-repo contract in section 1, alongside the WebSocket protocol, and either version it explicitly (a `/v2/send` path, matching check-in-relay's existing `/v1/` convention) or require relay and server changes to this contract to land as a coordinated pair, the same discipline recommended for client and server.

### 3. No compatibility policy for a single production relay serving many independently versioned self-hosted servers

Target: `oss.md` sections 1 and 3 (repository layout and versioning), against the brief's self-hosting requirement and the "official relay" model in `docs/BRIEF.md`.

Weakness: the brief describes one officially operated relay serving an open-ended population of self-hosted servers that upgrade on their own schedules, not in lockstep with the relay.
`oss.md`'s versioning section describes Conventional Commits and GitHub Releases per repository but never states a backward-compatibility commitment for the relay's HTTP API, even though the relay cannot be pinned per self-hosted install the way a client and its own server can be paired.

Failure mode: the maintainer deploys a new relay version that changes or removes a field the `/v1/send` contract used to accept.
Any self-hosted server still running an older release, which the brief explicitly expects to exist indefinitely since self-hosting means the operator controls upgrade timing, starts silently failing to deliver push notifications, with no version negotiation and no way for the self-hoster to detect the mismatch short of noticing missed notifications.

Resolution: state an explicit compatibility policy for the relay's public API (for example, additive-only changes within a version prefix, and a deprecation window before removing a field or endpoint), and document it in the relay repository's own contribution guide, not just implied by check-in-relay's existing `/v1/` path convention.

### 4. "Melos packages" as a compiler-checked guardrail has no working precedent in the cited reference project

Target: `oss.md` section 7, "Treat package and workspace boundaries (Cargo crates, Melos packages) as the primary enforcement mechanism, since a compiler-checked public API is a stronger guardrail than a style-guide sentence," and the section 8 rebuttal that a monorepo with "real workspace boundaries" is not what the brief's "avoid a giant monolithic codebase" principle means.

Weakness: echo-messenger's `apps/client` is a single Flutter package with one `pubspec.yaml`, organized only by folder convention (`lib/src/screens/`, `providers/`, `widgets/`, `services/`, `models/`).
There is no `melos.yaml` and no multi-package split anywhere in the repository.
Dart has no folder-level access control; nothing stops a file under `screens/` from importing an internal helper from `providers/` directly, and nothing in the reference project's tooling (lefthook, CI, SonarCloud config) checks for that today.
The Cargo-crate half of the claim is real (`core/rust-core` and `apps/server` are genuine, compiler-enforced workspace members), but the Melos half is aspirational, not proven, and the section 8 defense against the brief's "avoid monolith" wording leans on exactly this unproven half for the Flutter side.

Failure mode: a contributor adds a cross-layer import in the Flutter client that a real package boundary would have blocked at build time.
Nothing catches it until a reviewer notices in a PR, if they notice at all, which is the same style-guide-sentence failure mode the report says compiler-checked boundaries are meant to replace.

Resolution: either scope and cost an actual Melos-package split for the Flutter client as its own work item before claiming it as an enforcement mechanism, or drop the claim and rely on CODEOWNERS-gated directory review as the real Flutter-side guardrail, stating plainly that it is weaker than the Rust-side crate boundary.

### 5. Mixed first-party licensing within one monorepo has no stated enforcement mechanism

Target: `oss.md` section 2 (AGPL-3.0 for server, Apache-2.0 for client and shared protocol code, all inside the single core repository proposed in section 1).

Weakness: putting two different first-party licenses in one repository creates an ongoing risk that AGPL-intended server logic gets pasted into, or an AGPL-only dependency gets added to, the Apache-2.0 shared protocol crate, either by an inattentive contributor or by convenience during a refactor.
The report's own guardrails section proposes SonarCloud complexity budgets, a 300-line file lint, and CODEOWNERS, none of which check license correctness.
`deny.toml`, the tool the report implicitly leans on as precedent since it already governs the reference project's dependency licensing, enforces third-party dependency license bans; it does not verify that a specific first-party crate's own declared license, or its dependency graph, stays consistent with the license actually printed in that crate's `Cargo.toml` and header comments.

Failure mode: a shared protocol struct gains a convenience method that calls into server-only logic during a refactor, and the crate keeps shipping under its Apache-2.0 header while carrying code the server's AGPL obligations were meant to cover, so downstream consumers of the "permissive" client and protocol code get an inaccurate license signal and the AGPL network-copyleft lever the report designed the whole license split around is quietly weakened.

Resolution: add an explicit per-crate license check to CI, for example verifying each workspace member's `Cargo.toml` `license` field against an allowlist matching its intended license, and a review rule requiring any change that touches the shared protocol crate to get sign-off from someone who understands the license boundary, not just the technical one.

### 6. The relay repository's security and governance posture is underspecified for the one component named as holding live secrets

Target: `oss.md` section 1's stated reason for separating the relay ("a different trust boundary since it carries live push credentials") and section 6's governance model, which is written only in terms of the core repository.

Weakness: the report correctly identifies the relay as the sensitive component, then stops at "keeps those secrets out of the CI environment that builds client and server artifacts."
It never specifies branch protection, required-review rules, or restricted merge rights for the relay repository specifically, even though that repository's `internal/config` and admin-token comparison code is exactly the code a compromised or malicious PR would target.
DCO sign-off, the report's chosen provenance mechanism, proves who authored a commit; it does no code-intent vetting at all, and the report does not layer any additional review requirement on top of it for the one repository it just finished calling out as higher trust.

Failure mode: a contributor with earned `feature/**` push access (per section 3's trust-tier model) submits a subtly malicious change to the relay's credential-loading or admin-token comparison path, DCO sign-off is present and satisfies the only stated provenance check, and the change merges without any relay-specific review requirement beyond what applies to the low-risk core repository.

Resolution: state an explicit, stricter review policy for the relay repository in section 1 or section 6, for example mandatory maintainer review (not just any CODEOWNERS-eligible reviewer) on any change under `internal/config`, `internal/keys`, or the admin routes, and consider requiring signed commits for that repository specifically given what it holds.

### 7. Path-gated CI with no cross-repo contract test turns a relay protocol mismatch into a client-side battery cost

Target: `oss.md` section 3, "path-gated CI so a Dart-only change never rebuilds the relay," combined with the two-repo split in section 1.

Weakness: path-gating optimizes CI cost correctly within the core repo, but the report never proposes any automated check that the relay repository's understanding of the push envelope still matches what the server actually sends, since the two repositories have no shared CI, no shared schema source of truth, and (per finding 2) no compatibility contract either.

Failure mode: a push-envelope mismatch between server and relay ships without being caught by either repository's own CI, since each one only tests itself.
Real devices stop receiving wake pushes silently; `networking-relay.md` already establishes that push is the only mechanism for backgrounded mobile clients to know they need to reconnect, so the client-side fallback is to poll or reconnect more aggressively to avoid missing messages, which is a direct, measurable battery and network cost on iOS background execution, working against the brief's explicit battery and efficiency goals, and traceable back to an organizational decision (no cross-repo contract test) rather than a code bug.

Resolution: add a minimal cross-repo contract test, for example a shared JSON schema or fixture file for the push envelope that both repositories validate against in CI, or a scheduled integration job that exercises a real relay instance against the server's current push-encoding code.

## Minor findings

### 8. `check-in-relay` currently has no license at all

Target: `oss.md` section 1, "extending `check-in-relay` directly," and section 2's AGPL-3.0 verdict for the relay.

Weakness: `check-in-relay`'s repository root has no `LICENSE` file today, confirmed by direct inspection.
Under default copyright rules that makes it all-rights-reserved, not open source, so "extending" it as the basis for an "open source friendly" relay repository skips an unstated step: check-in-relay itself needs an explicit AGPL-3.0 (or compatible) license added before or as part of the fork.
This is a trivial fix since the same person owns both projects, but the report states it as if the starting point is already open, which it is not.

Failure mode: none if caught early; if missed, the relay repository launches without a clear license file, or with one added late after outside contributors have already assumed a license that was never actually granted on the code they built against.

Resolution: add one sentence to section 1 or 2 noting that `check-in-relay` needs its own `LICENSE` file added as part of the fork, before external contribution is invited.

### 9. Governance is scoped only to the core repository, with no equivalent for the relay

Target: `oss.md` section 6, `MAINTAINERS.md` and `CODEOWNERS`, written without reference to which repository they apply to.

Weakness: the report's own layout puts the relay in a second, separate repository, but section 6 never states whether `MAINTAINERS.md`, `CODEOWNERS`, and the criteria-based maintainer-promotion path apply there too, or whether the relay gets its own, lighter-weight version given its smaller expected contributor pool.

Failure mode: the relay repository launches with no `CODEOWNERS` file and no documented maintainer path at all, simply because section 6 was written with only the core repo in view, leaving exactly the higher-trust component (per finding 6) with the least formal governance.

Resolution: state explicitly that both repositories get their own `MAINTAINERS.md` and `CODEOWNERS`, even if the relay's is a one-line file naming the same single owner.

### 10. Process weight is justified inconsistently against the report's own "avoid premature complexity" standard

Target: `oss.md` section 6, which rejects a foundation or steering committee as "process weight the project has not earned," against sections 3, 5, and 7, which mandate bot-enforced DCO, commitlint, lefthook, path-gated CI across two repositories, three issue templates, a PR template, a decision-of-record folder, and org-wide SonarCloud complexity budgets, all before a single external contributor has joined.

Weakness: the report applies "not earned yet" to one category of process (formal governance) and "adopt immediately" to another (contribution and quality tooling) without stating why the second category is exempt from the same standard.
Some of this tooling is genuinely cheap to stand up (a PR template is a text file), but bot-enforced DCO, a two-repository CI matrix, and SonarCloud budgets extended "project-wide" are real, ongoing maintenance surface for a project the same report describes, in the same breath, as having exactly one maintainer today.

Failure mode: none of this is wrong in isolation, but a single maintainer now owns two CI pipelines, a bot integration, and an organization-wide static-analysis budget before there is a second contributor to justify the automation, which is time spent on process rather than on the product the brief prioritizes.

Resolution: either apply the same "earned, not assumed" test used for governance to the tooling recommendations, phasing in DCO enforcement and org-wide SonarCloud budgets once external contributions actually start arriving, or state explicitly why contribution tooling is exempt from the standard applied to governance structure.

### 11. The report's own flagged growth risk already has a visible, present-day example in the cited reference project

Target: `oss.md` section 1's risk note, "the core repo will grow large over years; path-gated CI and workspace boundaries must be actively maintained, not assumed."

Weakness: echo-messenger, the reference project the report treats as proof the monorepo pattern "works at this scale," already carries a top-level `TECHNICAL_DEBT.md` of roughly 90 KB and a `RESEARCH.md` of roughly 35 KB, alongside separate `docs/` subfolders for audits, known issues, a domain migration, a crypto audit, and group end-to-end-encryption design, on top of the actual `apps/server`, `apps/client`, and `core/rust-core` code.
That is direct, present-day evidence of the exact risk the report names, sitting in the same repository the report cites as proof the pattern is manageable.

Failure mode: none directly, but the report understates the risk by naming it as a future concern rather than pointing to concrete, already-realized accumulation in its own reference case, which would have made "actively maintained, not assumed" a more urgent instruction with a real annual cost attached rather than an abstract caveat.

Resolution: cite echo-messenger's actual documentation footprint as the evidence for this risk, and consider naming a concrete maintenance practice (a periodic docs-pruning or archival pass) rather than leaving "actively maintained" undefined.

## Closing note

The licensing verdicts in `oss.md` are the strongest part of the report and do not need rework: AGPL for the server and relay, Apache-2.0 for the client, and dropping PolyForm Noncommercial are all well reasoned and correctly grounded in the brief.
The weaker half is repository layout, where the report's own client/server coupling argument, that a shared wire protocol forces atomic co-review, was not applied to the equally real server-relay push envelope, and where the reference project is cited as proof for two things it does not actually demonstrate: a compiler-enforced Flutter package boundary, and a mixed-license monorepo.
None of this requires abandoning the two-repo split or the AGPL/Apache-2.0 split; it requires naming the second protocol boundary honestly, adding a compatibility policy for the one shared production relay, and being explicit that the Melos and license-boundary guardrails are proposed, not proven, before the plan is treated as validated by echo-messenger's track record.
