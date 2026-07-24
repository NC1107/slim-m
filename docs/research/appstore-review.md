# Adversarial Review: App Store and Play Store Compliance

Status: pre-implementation red-team of `docs/research/appstore.md`.
Reviewer stance: attack the plan before code exists, name a specific target and a concrete failure mode for each challenge, and reserve "critical" for issues that would force a redesign.
Reference repositories were consulted directly: `check-in-relay`'s source tree has no `internal/apns` package and no VoIP or PushKit code anywhere, confirmed by directory listing and a repo-wide grep for `apns`, `voip`, and `pushkit`.
Two live web searches were run to check load-bearing external claims: Apple's 13+/16+/18+ age-rating overhaul and its January 31, 2026 questionnaire deadline are real and match the report; a specific "Apple pressured Mastodon developers over CSAM" incident could not be independently confirmed, so the CSAM finding below is grounded instead in the documented Stanford Internet Observatory July 2023 study, which is real and directly on point.

## What holds up

The age-rating tier mechanics are accurate: Apple is retiring 12+ and 17+ in favor of 13+, 16+, and 18+, with a January 31, 2026 questionnaire deadline, confirmed independently.
The ReplayKit 50 MB memory ceiling and Android 14's removal of cached MediaProjection consent are both correct, well-documented platform constraints, and the report is right to flag them as engineering budget items rather than policy choices.
The instinct to promote account deletion from a client feature to a protocol verb is directionally correct and matches `security-review.md`'s own M7 finding.
Google Play's requirement for a public, non-app URL for account and data deletion is an accurate, already-existing policy, not a 2026 addition, and the report's proposed docs-page fix is reasonable.
The core Sign in with Apple analysis for a purely self-hosted-only client (no official instance) would be sound and matches real precedent from federated apps.

## Critical

### C1. The "no guideline targets self-hosted backends, risk: none identified" verdict does not survive the child-safety case, and the plan has no answer anywhere

Target: the verdict summary line "Invite-code, no-email-verification account creation on self-hosted servers does not conflict with either store's policy," and the "Client apps connecting to user-provided servers" section's risk line, "None; this is confirmation of the brief's existing architecture."
Moderation tooling (report, block, moderation queue) is scoped to the reference server per this report and per `backend.md`.
Any third-party fork of the open-source server can ship with report, block, and the moderation queue stripped out entirely, since AGPL and the protocol conformance suite (per `oss.md` and the open questions in this report) govern licensing and deletion, not moderation feature parity.
The official slim-m app remains the access point to that fork's content regardless.
The Stanford Internet Observatory's July 2023 study of the Mastodon fediverse found exactly this failure mode in a structurally identical architecture: decentralized instances with no built-in mechanism to report CSAM to child-safety organizations, alongside confirmed CSAM hash matches.
`security-review.md` already flags CSAM hash-matching and legal reporting exposure for the official instance as an open question with "no committed answer," and `backend.md` independently flags that real content moderation may not even be technically possible if the server never sees plaintext.
This report inherits both open questions without resolving either, then declares the connect-to-any-server architecture risk-free.
Concrete failure: a self-hosted fork drops moderation entirely, or the official instance's own moderation queue never gets a CSAM detection or NCMEC reporting pipeline because no report specifies one, and a store trust-and-safety review or a legal complaint lands on the official app regardless of which server was actually running.
Severity: critical, because the fix is not a doc update.
It requires new cross-cutting work absent from all eight specialist reports: a legal CSAM-reporting pipeline for the official instance, and either a fork-capability negotiation the client can check before rendering content from an unknown server, or an explicit, reviewed policy decision to accept that self-hosted forks are outside the maintainers' moderation control and say so publicly.
Resolution: do not close this as "none identified."
Commission a dedicated CSAM/legal-reporting design pass before v1, scoped narrowly to the official instance's reporting obligations and to what, if anything, the client can verify about a fork's moderation capabilities before connecting.

## Major

### M1. The relay's CallKit-compliant call-push path is described as already satisfying policy, but it does not exist yet anywhere in the reference code

Target: "Push via the official relay," specifically "the relay's `kind=call` routing and mandatory CallKit report already satisfies this."
Verified directly against the reference repository: `check-in-relay/internal` contains only `config`, `fcm`, `keys`, `api`, and `ratelimit`.
There is no `apns` package, no VoIP topic handling, and no `kind` field of any sort in the current send path, which only forwards `{token, title, body, data}` to FCM.
`networking-relay.md` proposes the entire APNs-native path, the `kind` field, and the `.voip` topic as new work, and `media.md` lists "whether PushKit VoIP token registration is in scope for the push relay's first version" as an open question.
Concrete failure: a reader of this report reasonably concludes the CallKit invariant is a shipped, tested behavior needing only "a regression test, not just a design note," when in fact the entire call-push subsystem, the compliance-critical part per Apple's own VoIP-entitlement enforcement history, is unbuilt, unscheduled, and owned by two other reports that have not finished designing it.
Severity: major, because treating unbuilt policy-critical infrastructure as done risks it being scheduled and tested like a small fix instead of budgeted as the cross-cutting, multi-repo build item it actually is.
Resolution: rewrite the section to state plainly that the APNs/.voip/kind=call path does not exist yet, cite it as a hard v1 dependency blocking the CallKit-report test, and cross-reference the two reports that still have it as an open question.

### M2. Nothing in the relay design stops a malicious or buggy self-hosted server from spamming `kind=call` pushes, and the entitlement risk that creates sits entirely with the official app

Target: the same "already satisfies this" claim, plus the recommendation to treat VoIP misuse purely as an internal regression-test problem.
`networking-relay.md`'s own send path lets any home server (official or self-hosted, the maintainers do not control the latter) submit `kind=call` events through the relay, gated only by a per-device rate cap, not by any check that a call is real.
`security-review.md` already notes a compromised relay could fabricate call wakes; the same is true, with a lower bar, of any self-hosted server the client trusts, since the server itself decides what kind to send.
Concrete failure: a hostile or simply buggy third-party fork pushes repeated `kind=call` events at a victim device up to the rate ceiling; the app must synchronously report each one to CallKit per the stated invariant, so the user's phone rings for calls that do not exist, a harassment vector and a battery and UX cost that lands on the official app's App Store standing even though the maintainers do not operate the offending server.
Apple's enforcement history in this report is about entitlement misuse, not entitlement abuse-by-proxy from a federated backend, and none of the eight reports design a defense (per-server call-push reputation, a user-facing mute for a specific server's calls, or tighter proof-of-legitimacy at the relay).
Severity: major.
Resolution: add a defense at the relay or client layer against abusive-but-technically-well-formed call pushes from a given server identity, distinct from the existing per-device volume cap.

### M3. The dual-mode account model is architecturally different from the Mastodon and Matrix precedent the 4.8 analysis leans on, and that gap is not disclosed as residual risk

Target: "Sign in with Apple, guideline 4.8," specifically "Risk: none identified, this is a stable, well-precedented reading," and the analogy to Ivory and Element.
Ivory and Element are pure federated clients: every server a user picks, including any default, is symmetrically third-party, with no privileged first-party account system baked into the app.
slim-m is not that shape.
The same app binary offers a first-party "official instance" with its own account system, marketed as the default, sitting alongside a generic third-party-server login path in the same login flow.
Apple's 4.8 exceptions are written and reviewed by humans against "exclusively uses your own account system" versus "client for a specific third-party service," and a mixed app that does some of each is a materially different shape from either precedent example, not a confirmed instance of it.
Concrete failure: a reviewer reads the official-instance path as the app's real primary account system (since it is first-class, marketed, and defaults are what most users take) and asks why Sign in with Apple parity is missing from it, treating the self-hosted path as a secondary feature rather than the thing that earns the exception.
Severity: major, not critical, because the fix if it happens is a contained addition (SIWA on the official-instance path only), not a redesign.
Resolution: state this as a genuine open question rather than a settled one, and prepare App Review notes explaining the dual-path model explicitly rather than hoping the reviewer infers it from Mastodon precedent.

### M4. Account deletion as a wire-protocol verb does not by itself satisfy 5.1.1(v) if the append-only audit log leaves user content and identifiers intact

Target: "Account deletion, guideline 5.1.1(v)," specifically the instruction to "promote account deletion to a mandatory verb in the wire protocol."
`security-review.md`'s M7 already flags that the security design mandates an append-only audit log and message retention, and never reconciles that with deletion.
This report treats verb existence as the compliance target, but 5.1.1(v)'s actual intent is that account data is meaningfully gone, and Apple has previously rejected deletion flows that amount to deactivation in substance.
Concrete failure: the reference server ships a `delete_account` RPC that flags the account as removed while message content, audit-log entries, and moderation records referencing that user persist unchanged, satisfying the letter of "a delete verb exists" while functionally matching the "disabling is not sufficient" case the guideline explicitly names.
Severity: major.
Resolution: specify, in this report or the one that owns data modeling, exactly what deletion purges versus tombstones versus retains, and confirm that shape actually clears the 5.1.1(v) bar rather than assuming a verb's existence does.

### M5. The report never addresses what covers Voice Canvas participation continuing in the background without an active CallKit call, a gap between its own background-mode guidance and a promise made elsewhere

Target: "Voice call background modes," specifically "never the `audio` background mode."
`ux.md` promises that "backgrounding the app keeps voice connected briefly inside the existing resume window rather than dropping it instantly," described as covering the call-and-canvas-as-one-screen experience, not only the voice audio stream.
`UIBackgroundModes: voip` legitimately covers continued execution while CallKit has an active, reported call, which covers voice audio.
It does not obviously cover continued Voice Canvas state sync (cursor positions, stroke events, object moves) for a participant who has muted or is canvas-only, since that is not audio and is not the incoming-call case PushKit exists for.
Concrete failure: the "brief resume window" ux.md promises for canvas participation has no named App Store-compliant background execution mode anywhere across the eight reports, and the default iOS background task budget (roughly 30 seconds) may be all that is actually available, silently undercutting a UX guarantee made in a sibling report.
Severity: major.
Resolution: either confirm canvas-without-audio backgrounding rides inside the same active VoIP-call background window and say so explicitly, or flag the resume-window promise as needing a scoped-down fallback.

### M6. Android's full-screen incoming-call intent is not a guaranteed UI on Android 14+, and the report states it as if it were

Target: "Voice call background modes," Android section, "use a `CallStyle` notification with a full-screen intent for the ring UI."
Android 14 restricted `USE_FULL_SCREEN_INTENT` so it is auto-granted only to apps registered as the device's default dialer or alarm app; other apps must direct the user through a dedicated settings screen to grant it, and Play Console increasingly scrutinizes the permission's declared use case.
`flutter-client.md` defers all Android platform integration, including this exact seam, to a later phase, so this permission-grant UX has no owner in the current plan.
Concrete failure: on a stock Android 14+ device that has not separately granted the permission, an incoming voice call silently degrades from a full-screen ring UI to a heads-up notification, a real product regression the report's "functionally parallel to PushKit" framing does not anticipate.
Severity: major.
Resolution: design the first-run or first-call permission request flow for `USE_FULL_SCREEN_INTENT` explicitly, and note the degraded-notification fallback path as an intended, tested state rather than an accidental one.

### M7. "Ship a moderation queue at launch" assumes staffing and response-time capacity that conflicts with the project's own single-owner governance model at the scale the official instance is sized for

Target: "User-generated content moderation," "Ship report, block, and a moderation queue at launch," read against Apple 1.2's requirement for "timely response" to reports.
`oss.md` states current governance is "a single owner acting as maintainer today," with a documented but slow path to add maintainers.
`networking-relay.md` plans the official instance's push volume for "thousands of self-hosted servers and low hundreds of thousands of devices at a mature v1."
Concrete failure: 1.2 obligates a timely response to reports, and a moderation queue with real UGC volume behind a single unpaid maintainer is a staffing problem this report does not surface, let alone solve; a store review that samples slow or unanswered reports on the official instance is a policy failure the moderation-queue feature's mere existence does not prevent.
Severity: major.
Resolution: state an explicit target response-time SLA for the official instance's queue and reconcile it with `oss.md`'s governance capacity, even if the honest answer is "response time degrades as a known risk until a co-maintainer is added."

### M8. Push-token privacy disclosure is scoped to the relay, but the app's Data Safety and App Privacy forms cannot be truthfully completed for a client that connects to an arbitrary, unenumerable set of third-party servers

Target: "Push via the official relay," "declare push tokens as collected 'Device ID' data in the App Privacy nutrition label and Play's Data Safety form."
Both forms ask what data the app shares with third parties, a question written for a fixed, known set of vendors.
slim-m's actual third-party data recipient set is "whatever self-hosted server the user chooses to type in," unbounded and unknown to the publisher at submission time, since a self-hosted server can log IP addresses, message metadata, and device identifiers on its own, entirely outside the relay's scope this report describes.
Concrete failure: the publisher completes the forms accurately for the relay and the official instance, but the forms as filed describe only a fraction of the app's actual real-world data flows, since any self-hosted server a user connects to is functionally a third-party data recipient the form has no field to enumerate.
Severity: major, because this is the same disclosure problem Mastodon and Matrix apps already live with, but this report does not name it or point to how those apps' listings handle it, leaving the team to rediscover the problem at submission time.
Resolution: research and document how comparable federated-client apps phrase this in their privacy disclosures, and add explicit language to the app's own privacy policy disclaiming publisher visibility into self-hosted server data practices.

## Minor

### m1. The report gives no App Review reviewer-instructions or demo-account plan for an invite-gated, self-hosted-capable app

Target: the report as a whole; no section addresses App Review testing logistics.
`ux.md` independently notes the self-hosted path must be first-class in the UI, not hidden, precisely because Apple scrutinizes apps that depend on an external, undisclosed service.
Concrete failure: a reviewer with no invite code cannot test self-hosted server connection, screen share, voice calls, the Voice Canvas, moderation tooling, or account deletion against a self-hosted target, since the brief's self-hosted flow requires an invite by design; without demo credentials and a standing demo self-hosted server documented in the App Review Information field, the reviewer either cannot evaluate the app's most architecturally distinct feature or is left to judge it from the official instance alone.
Resolution: budget a maintained demo self-hosted deployment and reviewer notes as a release-checklist item, not an afterthought.

### m2. Google Play's own content-rating questionnaire (IARC) and target-audience declaration are never addressed, only Apple's tiers

Target: "Age rating," which discusses only Apple's 13+/16+/18+ overhaul.
Play uses a separate IARC-based questionnaire and a distinct "target audience and content" declaration with its own Families Policy implications if the declared audience could include minors.
Concrete failure: the team completes Apple's new questionnaire carefully per this report's guidance and then treats Play's rating as an afterthought, risking an inconsistent age posture across stores for the same UGC and voice content, or missing a Play-specific obligation (such as ads or SDK restrictions tied to a broader target-audience answer) that has no Apple equivalent to prompt it.
Resolution: add a Play IARC and target-audience-declaration pass alongside the Apple age-rating work, not folded silently into it.

### m3. Eventual Linux desktop distribution through Flathub or a similar store carries its own content-rating system (OARS) that this report's age-rating work does not feed

Target: the report's scope, which is entirely App Store and Play Store.
The brief prioritizes Linux (Fedora) as a primary v1 platform, and Docker/GHCR-first, self-host-friendly projects commonly end up distributed via Flathub, which requires OARS content-rating metadata, a third, separate rating exercise.
Concrete failure: nobody notices this until a Flathub submission is blocked or mis-rated, since none of the eight reports name Flathub or OARS at all.
Resolution: note this as a future-scope item now, even briefly, so it is not rediscovered cold at desktop-release time.

## Gaps the specialist never addressed

Legal reporting obligations for CSAM on the official instance, likely including U.S. mandatory-reporting requirements for electronic communication service providers, are named as an open question in `security-review.md` and inherited silently here without resolution; this report is the one whose domain is store and legal compliance, and it is the one that should have closed this gap rather than passed it through.

The interaction between "18+ declared" and the fact that neither store enforces age ratings with verified identity is not discussed; an 18+ label changes parental-control visibility, not who can actually download or use the app, which matters for how much protective weight the recommendation is actually buying against the UGC and voice risk it is meant to offset.

No section discusses what happens to the official app's store listing if a self-hosted fork or even the reference server itself is later found hosting genuinely illegal content; there is no incident-response or emergency-delisting-avoidance plan, despite the moderation and legal gaps above making this a live scenario, not a hypothetical one.

TestFlight and Play internal/closed testing tracks are not discussed, despite `networking-relay.md` flagging TestFlight APNs sandbox credentials as its own open question; a testing-track review is still a review, and self-hosted-server testing logistics apply there too.

## Overall

The report's mechanical guideline-matching is careful and mostly correct where the guidelines are static text: the 4.8 exception language, the age-rating tier mechanics, the ReplayKit and MediaProjection platform constraints, and the Play deletion-URL requirement all check out.
Its weaknesses are the same shape as the other specialist reports' weaknesses: it treats unbuilt cross-cutting infrastructure (the relay's call-push path) as already satisfying policy, it declares "risk: none identified" in the one place a real, precedented, and store-relevant risk exists (decentralized UGC and child safety), and it does not reconcile its own recommendations with governance capacity, background-execution reality, or the account-deletion data model that other reports already flag as unresolved.
None of this requires abandoning the plan's core reading of the guidelines, which is sound.
It requires the report to stop marking cross-report dependencies as closed when they are open, and to treat the child-safety and moderation-capacity gaps as the launch-blocking design work they are, not as residual risk to note and move past.
