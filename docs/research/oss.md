# Open Source Strategy and Repository Structure

Status: pre-implementation research, feeds into STRATEGY.md.
Scope: repository layout, licensing per component, contribution workflow, documentation structure, issue and PR templates, governance, and guardrails that keep the codebase componentized as outside contributors join.
Assumes the stack already committed in the sibling reports: Rust/Axum server, Go relay extending check-in-relay, Flutter/Melos client.

## 1. Repository layout: two repositories, not one and not three

Verdict: two repositories.
A core monorepo, this repository, growing to hold `server/`, `client/`, and any shared protocol definitions alongside the existing `docs/`, holds the Rust server and the Flutter client together.
A second, separate repository holds the push relay, extending `check-in-relay` directly rather than folding it into the core repo.

Rationale for keeping client and server together: the WebSocket wire protocol is the one artifact both sides must change atomically.
realtime-sync.md already treats ordering and sequencing as a day-one contract, not a follow-up.
A protocol change split across a server PR and a separately merged client PR reintroduces the cross-side version skew that produced echo-messenger's canvas divergence bugs, moved from a data-sync problem into a release-choreography problem.
Echo-messenger already proved a single Cargo-workspace-plus-Flutter monorepo works at this scale, keeping CI fast through path-gated builds where only changed platforms get built; that pattern transfers directly.

Rationale for keeping the relay separate: it is a different language, a different release cadence since it should change rarely once APNs/FCM integration is stable, and a different trust boundary since it carries live push credentials.
Its own repository keeps those secrets out of the CI environment that builds client and server artifacts, and keeps most contributors, who never touch push infrastructure, away from that operational risk.
This also matches the brief's instruction to model the relay on `check-in-relay` directly rather than as a new subsystem of the main product.

Alternatives rejected: one repository for everything, including the relay, rejected on the secrets-exposure grounds above since most self-hosters and contributors never need relay code; and three fully separate repositories, rejected because it forces two-PR choreography for every client/server protocol change, the one place atomic co-review matters most, with no separate release cadences yet to justify the overhead.

Risk: the core repo will grow large over years; path-gated CI and workspace boundaries must be maintained deliberately, not left to happen. See guardrails below.

## 2. Licensing: network copyleft for services, permissive for the client

Verdict: the server and the relay ship under AGPL-3.0.
The Flutter client, and any shared protocol or schema definitions consumed by both client and server, ship under Apache-2.0.

Echo-messenger used PolyForm Noncommercial, a source-available license, not an OSI-approved open license.
That directly contradicts the brief's own stated principle, "open source friendly," and it discourages outside contribution: a contributor whose patch gets relicensed into a noncommercial-only codebase has good reason to hesitate, and companies with any legal review process will not touch it at all.
Continuing that choice for slim-m would be a mistake, not a neutral default.

The harder question is permissive versus copyleft for the parts that are genuinely open.
The brief describes an official hosted instance alongside encouraged self-hosting, the shape well-known self-hostable server products use AGPL for, to close the SaaS loophole: ordinary GPL only triggers source-sharing on distribution, so a well-funded operator can run GPL server code as a competing hosted service and never publish a line back, since running a service is not distributing software.
AGPL's network clause closes that gap; it is the only option among Apache-2.0, MIT, and GPL-3.0 that does.
For the client the calculus flips: AGPL on client code shipped through app stores has caused real friction historically, since copyleft terms forbidding additional restrictions can conflict with app store terms, and there is no SaaS-rehosting risk on a binary users install themselves.
Apache-2.0 beats plain MIT for the client and shared libraries for its explicit patent grant, meaningful once compiled binaries reach end users through app stores.

Alternatives rejected: Apache-2.0 or MIT for the whole project, which gives up the one lever, network copyleft, that protects the official-hosted-instance model from a rehoster; GPL-3.0 for the server, which has the same SaaS loophole AGPL exists to close; and keeping PolyForm Noncommercial, which contradicts the brief and suppresses contribution outright.

On contributor provenance, use a Developer Certificate of Origin sign-off, `git commit -s`, bot-enforced, not a full Contributor License Agreement.
A CLA matters mainly if the owner wants a future proprietary or dual-licensed offering; nothing in the brief states that intent, and "easy to contribute to" outweighs a hypothetical.
This is a real open question, flagged below.

Risk: AGPL is unfamiliar to some corporate contributors, and self-hosters who modify the server must understand they owe their own users source access, an obligation many do not expect from copyleft; document it plainly in the self-hosting guide rather than relying on the license text.

## 3. Contribution workflow

Reuse echo-messenger's proven shape: work happens on `dev` or `feature/**`/`fix/**` branches, merges to `main` via pull request, conventional commits enforced by commitlint and a pre-commit hook runner, and path-gated CI so a Dart-only change never rebuilds the relay.
External contributors fork and branch normally; trusted contributors, once promoted under the governance criteria below, get direct push to `feature/**`, mirroring echo's own trust tiers.
Conventional commit types drive automated semantic versioning and GitHub Releases, matching the brief's explicit requirement: `feat` bumps minor, `fix` bumps patch, a `BREAKING CHANGE` footer bumps major.

## 4. Documentation structure

Root-level `README.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` using the Contributor Covenant unmodified, `SECURITY.md` with a vulnerability disclosure contact and response window, and a short `ARCHITECTURE.md` mapping the codebase rather than duplicating the research reports.
`docs/research/` keeps the specialist reports as living reference, exactly as they exist today.
`docs/decisions/` replaces echo's `docs/voice-lounge/` naming with a subsystem-agnostic decision-of-record folder, one file per contract such as coordinate policy, sync ordering, or multi-device authority, each with status quo, options considered, a dated decision, and open questions, reusing the template the reference notes call unusually good practice.
The enforcement rule travels unchanged: a PR that changes a documented gesture, sync, or coordinate contract must update its doc in the same PR, not a follow-up.

## 5. Issue and PR templates

Three issue templates: bug report (repro steps, platform, version, logs); feature request requiring a problem statement before any proposed solution; and a template redirecting open-ended design discussion to GitHub Discussions rather than the tracker.
One PR template checklist: tests included, docs updated if a documented contract changed, a conventional-commit title (PR titles become release notes verbatim, proven in echo), and a DCO sign-off reminder.
Labels stay small: `good-first-issue`, `help-wanted`, per-component labels matching package boundaries, and bug severity.

## 6. Governance

Verdict: a single owner acting as maintainer today, formalized as `MAINTAINERS.md` and a `CODEOWNERS` file mapping directories to required reviewers, with a documented, criteria-based path to add maintainers (sustained quality contributions plus owner nomination) rather than governance by informal trust.
Reject a formal foundation or steering committee now; that is process weight the project has not earned, and it fights the brief's own instinct to avoid premature complexity.
Revisit once the contributor base spans multiple organizations with competing priorities, the point where informal governance actually breaks down.

## 7. Guardrails that keep the codebase componentized

Reuse and extend echo's proven SonarCloud budgets (cognitive complexity of 15, parameter count of 7, no nested ternaries) across every package, not just the client.
Turn flutter-client.md's soft 300-line file budget into a CI-enforced lint rule requiring an explicit override comment to exceed it, so the guardrail survives past the point where the owner can review every PR personally.
Treat package and workspace boundaries (Cargo crates, Melos packages) as the primary enforcement mechanism, since a compiler-checked public API is a stronger guardrail than a style-guide sentence, and route `CODEOWNERS` review at those same boundaries so a cross-package change always gets a second reviewer.
Keep a living "componentize before you paste twice" list of shared widgets and helpers, the same discipline echo's own `CLAUDE.md` already documents well.

## 8. A note on the brief's wording

The brief's "avoid a giant monolithic codebase" principle is about coupling and responsibility separation inside the code, not repository count.
Read literally, it would argue for splitting client and server apart, which section 1 rejects for good reason.
A monorepo with real workspace boundaries and path-gated CI is not what "monolithic" means; a repository split for its own sake would only move today's coupling problems into slower cross-repo choreography.
