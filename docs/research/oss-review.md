# Adversarial review: open source strategy (oss.md)

Status: adversarial review pass, pre-implementation.
Reviewed: docs/research/oss.md against docs/BRIEF.md, docs/decisions/0001-owner-decisions.md, docs/research/stack-decision.md, docs/research/devops.md, docs/research/flutter-client.md, docs/research/networking-relay.md, docs/research/media.md.
Method note: echo-messenger (decentralized-chat-app) was not opened at any point in this review, in line with the off-limits rule.
check-in-relay was opened only to verify two factual claims in oss.md, which is the allowed reference for the relay.
Both claims checked out: check-in-relay has no LICENSE file anywhere in its tree today, and its git history and remote show the same copyright owner as this project, so that owner can license the fork however they choose.
No language in oss.md leans on "the owner already has this" or "the existing pattern" as a rationale, and no structural echo of echo-messenger is visible from the reasoning given, so there is no evidence of a quietly reintroduced old-project pattern in this report.

Overall this is a competent, well-argued report with real first-principles reasoning behind every verdict.
The findings below are internal contradictions, an unweighed cost on the brief's own "open source friendly" goal, and a security-adjacent documentation gap, not evidence that the core repo-layout or licensing direction is wrong.
Nothing here rises to forcing a redesign, so no finding is rated critical.

## Major findings

### 1. The report contradicts its own two-repository verdict in the very same document

Section 1 is unambiguous: "A second, separate repository holds the push relay."
The relay is explicitly never in the same checkout as the server and client.
Section 3, describing CI, then says: "path-gated CI so a client-only change never triggers a server or relay build."
If the relay lives in a separate repository, there is no path inside the core repo's CI that could ever trigger a relay build in the first place, path-gated or not, so this sentence only makes sense if the relay was still mentally living inside the core repo when it was written.
Failure mode: an implementer reads section 3 literally and wires a relay build job into the core repo's CI matrix, recreating the exact three-toolchain-per-checkout problem section 1 rejected two paragraphs earlier.
Resolution: drop "or relay build" from that sentence, or replace it with a reference to the cross-repo contract test section 1 already specifies.

### 2. The file-length guardrail conflicts with a decision flutter-client.md already made independently

oss.md's guardrails section states: "Day one, regardless of language: a CI-enforced maximum file length with a reviewable override for the rare justified exception."
flutter-client.md, reasoning independently about the Dart package split, already settled on a different mechanism: "organize by feature vertical slice, with a soft 300-line file budget enforced at review."
One report wants a hard CI gate with a formal override process; the other wants a soft, human-judgment budget enforced only at review time, with no CI step named at all.
These are not compatible implementations of "the same guardrail," they are two different guardrails, and neither report acknowledges the other's existence.
Failure mode: whichever team implements CI first bakes in a hard-fail check that immediately starts rejecting files the Flutter team considers within its own agreed soft budget, or the Flutter team never gets a CI check at all because it believes review discipline already covers it.
Resolution: reconcile explicitly in one decision record naming which mechanism wins per language, since "regardless of language" is currently false for Dart as flutter-client.md is actually written.

### 3. The CI file-length cap never addresses generated code, and this stack generates a lot of it

The wire format decision (stack-decision.md section 5) is schema-first codegen: Dart types via json_serializable and freezed, Rust types via serde, both regenerated and diffed in CI on every schema change.
Generated model files from that pipeline routinely run to thousands of lines in a single file, and oss.md's file-length guardrail says nothing about excluding generated or build_runner output from the cap.
Failure mode: the first meaningful schema change trips the length cap on a file nobody hand-wrote, and the "reviewable override" that was meant to be rare becomes the routine path for every codegen commit, which trains reviewers to rubber-stamp the override and defeats the guardrail's purpose everywhere else.
Resolution: name the generated-file exclusion in the same guardrail decision, not as an afterthought discovered during the first real PR.

### 4. AGPL on the relay buys little of the protection it is chosen for, at a real contributor-friction cost

The stated reason for AGPL on the relay is closing the SaaS rehosting loophole: a competitor runs a modified version as a service without publishing changes back.
But the relay's own README (check-in-relay, the report's own reference point) describes a small, credential-gated forwarder: register, send, healthz, admin, with the real moat being possession of the Firebase and APNs credentials bound to the published app, not the source code, which anyone could rewrite from the documented API surface in a weekend.
AGPL does not protect a moat that is credential-based rather than code-based, but it does carry AGPL's well-documented cost: many companies' open source contribution policies flatly forbid employees from contributing to AGPL-licensed projects at all, not just from using them.
Failure mode: a willing contributor with relevant Go and push-notification experience is blocked by their employer's OSS policy from touching the one repository in the project that most needs outside eyes on its credential-handling code.
Resolution: re-examine whether Apache-2.0 plus a clear anti-rehosting trademark and branding policy achieves the real goal, stopping a competing "slim-m relay as a service" from using the name and reputation, without the contributor-access cost, given the credential moat already does most of the protective work AGPL is credited for here.

### 5. AGPL on the server is never weighed against the brief's own "open source friendly" and "easy to contribute to" goals

The report carefully weighs contributor and platform friction when it picks Apache-2.0 for the client: "AGPL terms have historically caused real friction against app store restrictions, a risk with no offsetting benefit here."
It applies no equivalent scrutiny to the server, where the same friction exists in a different form: the same corporate contribution bans that make finding 4 real for the relay apply equally to the server, which is the component most likely to attract experienced backend contributors given the brief's emphasis on componentized, high-quality server architecture.
Failure mode: the project's most technically demanding component, the one place where outside expertise would matter most, is the one component with the highest bar to legal contribution clearance for anyone at a company with a standard OSS contribution policy.
Resolution: at minimum, name this as an accepted tradeoff explicitly rather than silently applying a friction analysis to one component and skipping it for the other.

### 6. The report defers the very license-leakage guardrail it says is needed immediately

The licensing section says active enforcement, SPDX headers, a REUSE-style license map, a CI license-allowlist check, is needed "or AGPL-intended logic can leak into the permissive shared schema package," a risk framed as present now, since it can happen during any refactor.
The proportional-tooling section then lists what ships "day one" and explicitly defers "a formal per-package license CI matrix" until "once outside contributions land."
The leakage risk the first section names is not caused by outside contributors, it is caused by anyone, including the solo maintainer, moving code between packages during ordinary refactoring, so deferring the check does not defer the risk.
Failure mode: the highest-risk period for this specific leak is exactly the solo-maintainer period with no second reviewer catching a misplaced AGPL-derived function landing in the Apache-2.0 schema package, and that is precisely the period the phasing plan leaves unmonitored.
Resolution: either the license CI check is cheap enough to ship day one, in which case add it to the day-one list, or it genuinely can wait, in which case the risk framing in the licensing section needs to say so instead of calling it a live leakage risk.

### 7. The relay repository has no stated security-disclosure or ownership parity with the core repo

Section 1 puts the relay in its own repository specifically because it "holds live push credentials, an APNs key and an FCM service account."
Section 4 (documentation structure) specifies README, CONTRIBUTING, CODE_OF_CONDUCT, and SECURITY.md with a vulnerability contact, and section 5 (governance) specifies MAINTAINERS.md and CODEOWNERS, both written in the singular with no explicit statement that the credential-holding relay repository needs the same files.
networking-relay.md confirms the stakes: the relay's send path handles ciphertext and holds a signing key whose compromise is treated elsewhere in the project's own research as a serious incident, not a paperwork question.
Failure mode: a security researcher who finds a vulnerability in the relay's key-handling code has no repository-local SECURITY.md telling them where to report it, because the only one specified lives in a different repository entirely.
Resolution: state explicitly that every repository in the project, not just the core one, ships its own SECURITY.md, CODEOWNERS, and MAINTAINERS.md, sized down if needed but never absent.

## Minor findings

### 8. AGPL plus DCO-only compounds into a harder-to-reverse position than either choice looks alone

The report treats the DCO-versus-CLA choice as reversible later if a commercial plan emerges, and separately treats AGPL as settled with no such caveat.
The two interact: without a CLA, the project can never cleanly relicense away from AGPL later even if the maintainer wants to, since DCO sign-off certifies provenance but grants no relicensing right over past external contributions, so every past contributor would need to be tracked down for consent.
This is not a reason to add a CLA now, since nothing in the brief signals that intent, but the report's own "revisit only if a commercial dual-license plan is later adopted" framing for DCO quietly assumes a reversibility that the AGPL choice, sitting right next to it, has already foreclosed.
Resolution: note the interaction explicitly as an accepted, understood tradeoff rather than leaving two independently-reversible-sounding decisions that are not actually independent.

### 9. Day-one governance scaffolding is mild scope creep against the owner's own stated aversion to overcommitted process

The owner's decision on the moderation SLA explicitly grounds itself in "single-maintainer governance at friend-group scale, where a published SLA would be an overcommitment."
The governance section of oss.md asks for MAINTAINERS.md and CODEOWNERS on day one, which is cheap and fine, but also "a written, criteria-based path to add maintainers" before a single external contributor exists.
Failure mode: none severe, but it is process written for a problem, choosing among competing candidate maintainers, that does not exist yet, in a report that elsewhere correctly applies a "not earned yet" standard to license tooling and contract tests.
Resolution: fold the maintainer-addition criteria into MAINTAINERS.md whenever the first serious contributor actually appears, rather than drafting it speculatively now.

## What the report gets right, unchallenged

The two-repository split itself, separating the relay's language, toolchain, and credentials from the core client-plus-server-plus-schema repo, is well-argued and matches devops.md's independently-reached repo topology without either report citing the other, which is a reasonable convergence rather than a copied pattern.
The check-in-relay LICENSE gap finding is factually correct and the recommended fix is legally sound, since the same person holds copyright on both repositories.
The Rust workspace crate boundaries as the primary Dart-versus-Rust componentization guardrail, and the explicit admission that Dart has no equivalent for free, is an honest and accurate asymmetry, correctly handed off to the Flutter client's own report rather than hand-waved.
