# App Store and Play Store Compliance

Status: pre-implementation specialist report, feeds into STRATEGY.md.
Scope: the invite-code account model, Sign in with Apple (4.8), account deletion (5.1.1), client apps that connect to user-provided servers, push via the official relay, screen share and recording permissions, and voice call background modes.
Guideline numbers cite Apple's App Store Review Guidelines at developer.apple.com/app-store/review/guidelines, current as of the January 31, 2026 age-rating cutover, and Google's Play Console Developer Program Policies including the April 15, 2026 update.

## Verdict summary

Invite-code, no-email-verification account creation on self-hosted servers does not conflict with either store's policy.
Sign in with Apple is not triggered by either the official instance or self-hosted accounts.
Guideline 5.1.1(v) account deletion does apply and requires a protocol-level commitment, not just a client feature.
Screen share is governed by platform permission and entitlement rules, not by any guideline specific to self-hosted backends.

## Sign in with Apple, guideline 4.8

4.8 requires Sign in with Apple only when an app uses a third-party or social login service, such as Google Sign-In or Facebook Login, to set up or authenticate the app's own primary account.
Two exceptions in the current text cover slim-m directly.
The official instance falls under "your app exclusively uses your company's own account setup and sign-in systems."
Self-hosted accounts fall under "your app is a client for a specific third-party service and users are required to sign in to their mail, social media, or other third-party account directly to access their content," since the self-hosted server is the third-party service and the invite-created credentials are the primary account, not a delegated identity into a slim-m-owned one.
This is the same reasoning that lets Mastodon and Matrix clients such as Ivory and Element ship without Sign in with Apple.
Verdict: do not add any social login option in v1, since adding one later would immediately require Sign in with Apple in lockstep.
Risk: none identified, this is a stable, well-precedented reading.

## Account deletion, guideline 5.1.1(v)

5.1.1(v) states plainly: if your app supports account creation, you must also offer account deletion within the app, and disabling or deactivating an account is not sufficient.
This applies regardless of who operates the server, so the requirement lands on the official instance and every self-hosted deployment the official client can talk to.
The risk specific to slim-m is that self-hosted servers are third-party software the maintainers do not control at runtime, so a real user could connect to a server that omits a deletion endpoint.
Required adjustment: promote account deletion from an implementation detail to a mandatory verb in the wire protocol itself, implemented in the reference server from day one alongside the existing session and device-revocation model.
The client always shows a Delete Account entry in settings; if a connected server returns not-implemented, it shows a clear explanation and the operator's contact information rather than hiding the control, mirroring how Apple already tolerates heterogeneous server capability for Mastodon and Matrix apps.
Google Play's User Data policy additionally requires a public, non-app web URL where deletion can be requested, filled into the Data Safety form at the app-package level.
Required adjustment: publish a docs page describing in-app deletion for both account types, since the Play Console field cannot list one URL per self-hosted server.

## Client apps connecting to user-provided servers

There is no guideline that names "self-hosted backend" as a category.
The closest and most dangerous adjacent rule is 4.2.7 Remote Desktop Clients, which restricts apps that mirror a specific host device to LAN-only connections, host-initiated account management, and no App Store-like UI.
slim-m is not a remote desktop client: it is a native messaging protocol client with its own UI, account model, and offline data, the same category as Discord, Slack, and Matrix clients, all of which ship WAN-reachable screen share without falling under 4.2.7.
Risk: a reviewer could misclassify screen share as remote mirroring; mitigate by framing it as one feature among many, never full remote control of the host.
The general applicable rules are 4.2 Minimum Functionality, satisfied by a native Flutter UI rather than a wrapped website, and 1.2 User Generated Content, which requires filtering objectionable material, a report mechanism with timely response, the ability to block abusive users, and published contact information, already reflected in the security report's permission model and moderation queue.
Google Play's 2026 UGC policy adds one item not yet in the account model: users must accept the app's terms of use before creating or uploading content.
Required adjustment: add a lightweight terms-acceptance checkbox to invite redemption, distinct from email verification and no added friction.

## Age rating

Apple retired the 12+ and 17+ tiers on January 31, 2026 in favor of 13+, 16+, and 18+, and user-generated content plus unrestricted communication almost always raises the rating.
Verdict: declare 18+ for the official app, since unmoderated voice, screen share, and self-hosted UGC exceed the 16+ "unrestricted web access" threshold in spirit.
Open question: whether a custom server address field counts as "unrestricted web access" under the new questionnaire; treat 18+ as the safe default regardless, since UGC and voice alone justify it.

## Push via the official relay

No guideline targets relay architecture directly; the applicable obligations are entitlement discipline and privacy disclosure, both already covered by the networking and security reports.
2.5.4 restricts background services, including VoIP, to their intended purpose, and Apple has revoked the VoIP-push entitlement from apps that used it for anything other than reporting an incoming call to CallKit; the relay's `kind=call` routing and mandatory CallKit report already satisfies this, and it needs a regression test, not just a design note.
Required adjustment: declare push tokens as collected "Device ID" data in the App Privacy nutrition label and Play's Data Safety form, since the relay and home server both handle them even though content stays encrypted end to end.

## Screen sharing and recording permissions

iOS system-wide capture requires a ReplayKit Broadcast Upload Extension capped at 50 MB of memory, a hard OS-enforced limit, not a guideline, that the media report already flags for early load testing.
Guideline 2.5.14 requires clear visual or audible indication whenever the app records camera, microphone, or screen; iOS's system status indicator satisfies this automatically, and the app should not suppress or replace it.
Android's MediaProjection requires a declared `mediaProjection` foreground service type, and as of Android 14 the projection consent can no longer be cached across app restarts, so the client must re-prompt every session rather than attempt a silent-resume design.
Required adjustment: budget the extension's frame buffering against 50 MB from the first spike, and declare `mediaProjection`, `camera`, and `microphone` foreground service types separately with their own justification in Play Console, not one bundled declaration.

## Voice call background modes

iOS: `UIBackgroundModes: voip` paired with PushKit and CallKit is the only compliant path for incoming-call wake, never the `audio` background mode, which 2.5.4 restricts to genuine continuous playback and which reviewers reject as a generic keep-alive.
Android: declare the `phoneCall` (or `microphone` plus `camera`) foreground service type, use a `CallStyle` notification with a full-screen intent for the ring UI, and trigger it from a high-priority FCM message, the Android 14+ background-start exemption carved out for incoming calls, functionally parallel to PushKit.
Adopting Telecom's `ConnectionService` on Android gives system-level call UI, Bluetooth routing, and Do Not Disturb handling equivalent to CallKit, worth the integration cost over a custom in-app ringer.

## Required adjustments to the invite-based account model

Keep invite-code and invite-link signup with no email verification, unchanged from the brief; neither store requires it, and 5.1.1(v) favors less personal information, not more.
Add: a mandatory terms-of-use checkbox at invite redemption (Play's 2026 UGC policy).
Add: account deletion as a mandatory protocol verb, not an optional server feature, shipped in the reference server from v1, always visible client-side, with a non-hiding fallback message for non-compliant third-party servers.
Add: a public account-and-data-deletion docs URL for Play's Data Safety form, since it cannot list one URL per self-hosted server.
Avoid: any social login button in v1, keeping the 4.8 exception clean.
Ship at launch, not later: report, block, and a moderation queue, and declare the official app 18+.

Residual risk: a third-party server fork that omits the deletion endpoint is a real but low-probability review exposure, mitigated by treating deletion as a required verb in the protocol conformance suite rather than an optional capability.
Apple's age-rating questionnaire is new enough, effective January 31, 2026, that its treatment of server-address fields is not yet settled by precedent; watch review outcomes for comparable Matrix and Mastodon clients.
