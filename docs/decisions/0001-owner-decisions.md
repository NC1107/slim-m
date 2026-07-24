# 0001 - Owner decisions on the ten open planning questions

Status: accepted.
Date: 2026-07-23.

These are the project owner's decisions on the ten open questions that closed out the pre-implementation planning in [STRATEGY.md](../STRATEGY.md).
Each was presented with a recommended option grounded in the specialist and adversarial review passes.
Where a decision changes the plan, the change is reflected directly in STRATEGY.md and ROADMAP.md.

## 1. Encryption stance

Decision: transport-only for v1 (TLS 1.3, server holds plaintext), with per-user and per-device identity keys pre-wired so opt-in end-to-end encryption for DMs can be added later without a wire-format rewrite.
This confirms the recommended stance.
Rationale: full E2EE breaks history, search, sync, server-side moderation, and readable push, and is not lightweight; the self-host operator is already inside the content trust boundary.

## 2. Voice Canvas coordinate space

Decision: a very large bounded world (roughly plus or minus 5,000,000 logical pixels, Figma/Miro style) with client recentering, not literally unbounded coordinates.
This confirms the recommended option.
Rationale: stable floating-point precision, simpler viewport math, predictable culling and performance budgets, and it still feels infinite to users.

## 3. Child safety and content policy

Decision: no proactive or automated scanning of user content or media.
The platform does not monitor what users post.
Safety relies on manual user reporting plus the report, block, and moderation-queue tooling the stores require, with published contact info.
The official US-hosted instance acts on reports and reports known child-sexual-abuse material to the relevant authority (in the US, NCMEC) when it obtains actual knowledge, without running a hash-matching pipeline.
This overrides the earlier recommendation to commission a CSAM hash-matching pass.
Rationale (owner): the real App Store concern is the identifying-account requirement, not content policing; the target use is small self-hosted friend groups, not large public communities, and there is no monitoring duty for a provider that does not proactively scan.
Note: the client still verifies via a capability handshake that a server exposes report and block before connecting, since a third-party fork could strip moderation while the official app remains the access point.

## 4. Multiple communities per deployment

Decision: one backend deployment is one community in v1.
Multi-guild (one backend hosting several independent communities) is revisited post-v1 only if self-hosters ask.
This confirms the recommended option.
Rationale: much simpler data model, permissions, and UX, matching per-friend-group self-hosting, with lower idle overhead.

## 5. Read receipts visible to other users

Decision: deferred as a later opt-in.
v1 syncs a user's own read state across their own devices but does not show other users when a message has been read.
This confirms the recommended option.
Rationale: privacy-friendly default, less presence fan-out, and simpler.

## 6. Self-hosted account recovery

Decision: admin-issued one-time reset code only for v1.
No optional recovery email in v1 (this trims the recommended option, which had offered optional email alongside).
Rationale: fits the no-email invite model and the friend-group self-host case where the admin is reachable; recovery email can be added later if demand appears.
Accepted risk: if the admin is unreachable and no other path exists, a locked-out user cannot self-recover; acceptable at friend-group scale.

## 7. Official instance scaling

Decision: single-process with in-memory state behind a swappable interface; add a shared backplane only when scale actually demands it.
This confirms the recommended option.
Rationale: simplest and lightest, matches self-host reality, and avoids premature infrastructure everyone would pay for.

## 8. Design token validation

Decision: the accent teal and token palette get a real designer/stakeholder review before the primitive tokens are locked, alongside the automated WCAG contrast gate in CI.
This confirms the recommended option.
Rationale: the accent is a from-scratch brand choice and tokens are load-bearing across the whole UI, so catching brand and accessibility issues before lock is worth the step.

## 9. Project name

Decision: keep "slim-m" as the working name for now and revisit before 1.0.
This confirms the recommended option.
Rationale: unblocks Phase 0 immediately and renaming is cheapest before code exists.
This remains the one deliberately deferred item; a final name is chosen before the 1.0 release closeout in Phase 9.

## 10. Join/leave notification sounds and moderation SLA

Decision (sounds): default join/leave chimes play only in channels with roughly 8 or fewer participants and are muted above that, always user-overridable.
This confirms the recommended option.

Decision (moderation SLA): the official public instance publishes no fixed report-response service-level agreement.
It escalates illegal-content and safety reports on discovery.
This chose the lightest option over the recommended best-effort target.
Rationale: single-maintainer governance at friend-group scale, where a published SLA would be an overcommitment; self-hosted servers set their own policy.
