# Open Source Strategy and Repository Structure

Status: pre-implementation research, feeds into STRATEGY.md.
Scope: repository layout, per-component licensing, contribution workflow, documentation structure, governance, and guardrails against file bloat and coupling.
Builds on the stack already committed this pass: Rust/Axum/Tokio over SQLite, a Flutter client, a schema-first JSON protocol with CI-enforced Dart and Rust codegen, and a Go push relay adapted from check-in-relay.
Every decision below is argued from the brief, the owner decisions, and that stack alone.

## 1. Repository layout: two repositories

Verdict: two repositories.
One core repository holds the Rust server, the Flutter client, and the OpenAPI plus JSON Schema protocol definitions both consume.
A second, separate repository holds the push relay, forked and extended directly from check-in-relay.

Server and client stay together because the committed stack requires one schema-first source of truth with CI-enforced codegen for both Dart and Rust, plus additive-only version-skew rules, and that codegen only enforces anything if it runs against one schema in one CI job.
Splitting client and server across repositories turns an atomic schema-plus-handler-plus-screen change into coordinated two-repo releases, the choreography schema-first codegen exists to prevent.
A monorepo with real crate and package boundaries, not a flat namespace, keeps the coupling that actually matters, the wire protocol, reviewable in one pull request.

The relay stays apart because it is a different language and toolchain by construction, adapted from check-in-relay's existing Go codebase, and it holds live push credentials, an APNs key and an FCM service account, that most contributors never need to see.
It also has a different distribution model: the relay is only ever officially operated, never cloned and run by a self-hoster, unlike the server image every self-hosted deployment pulls, so folding it in adds a third language to every checkout for a component almost no contributor touches.

The server-relay boundary is still a real contract, not a free pass: the push envelope must stay additive-only and versioned with the same discipline applied to the client/server WebSocket envelope, with a contract test against a real relay instance before the surface is called stable, so drift fails loudly in CI rather than as silently missed pushes.

Alternatives rejected: one repository for everything, which drags relay secrets and a third toolchain into every checkout for no shared-schema benefit; three separate repositories, which forces two-PR choreography on every protocol change, the exact overhead schema-first codegen removes.

Risk: a monorepo can grow unbounded scope over years if nothing prunes it; path-gated CI, workspace boundaries, and a periodic docs and dependency pruning pass need to be a named recurring task, not assumed.

## 2. Licensing: network copyleft for services, permissive for the client

Verdict: the server and relay ship under AGPL-3.0.
The Flutter client and the shared protocol and schema package ship under Apache-2.0.

The project ships an official hosted instance alongside encouraged self-hosting, exactly the shape that makes the SaaS loophole real: plain GPL only triggers source disclosure on distribution, and running a modified server as a hosted service is not distribution, so a well-resourced operator could rehost it as a competing service and never publish a line back.
AGPL's network-use clause is the one option among Apache-2.0, MIT, and GPL-3.0 that closes that gap, and it applies equally to the relay, itself a network service rather than something end users install.

For the client the calculus differs: there is no rehosting risk on a binary a user installs on their own device, and AGPL terms have historically caused real friction against app store restrictions, a risk with no offsetting benefit here.
Apache-2.0 beats plain MIT for the client and the shared schema package for its explicit patent grant, which matters once compiled binaries reach end users through app stores.
The shared schema package stays permissive rather than inheriting the server's AGPL, since its generated code compiles directly into the client; a copyleft schema package would embed an AGPL artifact inside a permissively licensed app.

Alternatives rejected: Apache-2.0 or MIT project-wide, which gives up the lever protecting the hosted instance from an uncontributing rehoster; GPL-3.0 for the server, which carries the same SaaS loophole AGPL closes; AGPL for the client, rejected for app-store friction with no offsetting benefit.

Risk: a mixed-license monorepo needs active enforcement, since nothing stops server-only logic from being pasted into the shared schema package during a refactor.
Use per-package SPDX headers, a root license map following the REUSE convention rather than one ambiguous LICENSE file, and a CI check verifying each package's declared license against an allowlist, with mandatory review on any change to the shared schema package.

Separate finding: check-in-relay ships with no LICENSE file anywhere in its tree today, confirmed by direct inspection, which under default copyright makes it all-rights-reserved rather than open.
Add an explicit AGPL-3.0 LICENSE to check-in-relay as part of the fork, before external contribution to the relay repository is invited.

## 3. Contribution workflow: DCO, not a CLA

Verdict: a Developer Certificate of Origin sign-off, `git commit -s`, checked by CI, not a Contributor License Agreement.
A CLA earns its cost mainly when the maintainer wants a future proprietary or dual-licensed offering, and nothing in the brief or owner decisions states that intent; "open source friendly" and "easy to contribute to" argue against friction for a hypothetical.
Revisit only if a commercial dual-license plan is later adopted, since retrofitting a CLA after contributions exist is harder than starting with one.

Beyond provenance: conventional commits enforced by commit-lint, feature and fix branches merging to a protected main branch through pull request, and path-gated CI so a client-only change never triggers a server or relay build.
Conventional commit types drive the automated semantic versioning and GitHub Releases the brief requires.

## 4. Documentation structure

A root `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, and `SECURITY.md` with a vulnerability disclosure contact, plus a short `ARCHITECTURE.md` mapping the codebase rather than duplicating the research reports.
`docs/decisions/` continues as the existing decision-record home, extended to cover technical decisions alongside owner product decisions, one file per contract, dated, with options considered and an explicit status.
A pull request changing a documented contract, the wire protocol, an ordering rule, a coordinate policy, updates the matching decision file in the same pull request.

## 5. Governance

Verdict: a single maintainer today, formalized as `MAINTAINERS.md` and a `CODEOWNERS` file mapping directories to required reviewers, with a written, criteria-based path to add maintainers, sustained quality contributions plus nomination, rather than governance by informal trust.
This matches the owner's own posture on the moderation-SLA decision: single-maintainer governance at friend-group scale, where heavier process is an overcommitment.
A formal foundation or steering committee is out of scope until contributors span multiple organizations with competing priorities, the point where informal governance actually breaks down.

## 6. Guardrails against file bloat and coupling

The brief's goal is componentized, low-coupling code that stays maintainable as strangers submit patches, so guardrails need tooling, not memory.
On Rust, workspace crate boundaries with deliberately narrow `pub` surfaces are the strongest guardrail, since a crate boundary is compiler-checked, unlike a style-guide sentence; route `CODEOWNERS` review at those boundaries so a cross-crate change always gets a second reviewer.
Dart has no folder-level access control: nothing stops one feature reaching into another's internals unless the client is split into packages with path dependencies, real engineering work and cost, not a free guardrail, and the Flutter client's own decision to make.

Day one, regardless of language: a CI-enforced maximum file length with a reviewable override for the rare justified exception, and a complexity lint, clippy's complexity lints on Rust and `dart analyze` plus a custom lint set on Dart, rather than an external dashboard depended on immediately.
A dependency-license check, `cargo-deny` for Rust and an equivalent allowlist for Dart, keeps AGPL-incompatible licenses out of the Apache-2.0 client; this is also where a UI dependency such as the Lucide icon set gets its license verified once, not assumed.

Proportionality matters as much here as in governance: not everything needs to exist before the first external contributor shows up.
Day one needs only DCO enforcement, commit-lint, path-gated CI, and file-length plus complexity linting, cheap checks that catch real problems immediately.
A formal per-package license CI matrix and a cross-repo contract test can phase in once outside contributions land.

## Open questions

Whether a future commercial offering is wanted, which would change the DCO-versus-CLA call, and whether the relay needs a published API compatibility policy once more instances depend on it.
