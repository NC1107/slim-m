# Moderation and safety review - merged

Three independent lenses (frontend implementation, UX/accessibility, backend/contract) reviewed the same screenshot set and code paths, merged here per screen or family.

## What this covers

The moderation and safety surface: the member popover's eleven permission/state tiers, the member profile popover and its Remove-from-Space/Eject confirmations, the report queue card's nine variants, the report dialog, the four blocked-DM notice states, and the four safety-capability notices.
Scope: `build/ui-capture/images/overlays/{member-popover,member-profile-popover,report-card,report-dialog,dm-blocked,safety-notice}-*.png`, 28 images, against `member_profile*.dart`, `safety_actions.dart`, `member_actions.dart`, `blocked_dm_notice.dart`, `server_notice.dart`, `report_card*.dart`, and their server-side counterparts in `http/members.rs`, `http/voice.rs`, `http/messages.rs`, `http/reports.rs`, `store/dms.rs`, `store/timeouts.rs`.

## The short version

- A moderator holding only `KICK_MEMBERS`, looking at an already-timed-out member with no shared call, gets a "MODERATION" section header with nothing beneath it, found independently by two lenses at the same root cause.
- "Delete message" on a report card checks the caller's deployment-wide `MANAGE_MESSAGES`, but the server checks it per channel, and for a DM message report that permission is structurally unreachable for anyone, making the button a guaranteed dead click on exactly the report class this codebase built visibility for.
- "Eject from call..." checks the same wrong deployment-wide scope, hiding a real, working per-channel capability from a moderator who holds `KICK_MEMBERS` only via a channel or voice overwrite.
- The report reason is the one piece of prose on a report card with no label, unlike everything else on it, which the card's own design principle already covers for every other field.
- Whether the blocked-by-them failed-send screenshot leaks anything is disputed between lenses: one reads it as byte-identical to a generic failure and clean, the other finds the screenshot's text is a hand-authored fixture that does not match what the real code path produces.
- Report-and-block stays one shared implementation, danger actions stay outlined-never-filled everywhere, and the blocked-DM composer genuinely shows nothing block-aware before a send is attempted.

## Member popover - the moderation section and timeout badge

Verdict: the badge itself is the best copy in the whole review; the section composed around it has one real broken combination and one accurate-but-incomplete summary.

- **A moderator with only `KICK_MEMBERS`, viewing an already-timed-out target with no shared call, gets a "MODERATION" header over nothing.**
  Found independently by the frontend and UX lenses at the identical root cause, `member_profile.dart:306-307`.
  `showModeration` is `canTimeOut || canRemove || canManageRoles || canEject`, computed from raw permission bits.
  The row that would represent `canTimeOut` is gated separately, at `member_profile.dart:386-387`, on `profile.timedOutUntil == null` (correctly suppressed while a timeout is already active, since the badge above already carries it).
  When `canTimeOut` is the only true bit and the target is already timed out, `showModeration` stays true, so the divider and `AppMenuLabel('Moderation')` render followed by four `if`s that all evaluate false.
  `AppMenu`/`AppMenuLabel`/`AppMenuDivider` (`design_system/lib/src/components/surfaces/menu.dart`) have no logic to elide an empty section; they render exactly what they are given.
  Confirmed in `member-popover-timeout-badge-liftable-desktop.png` and `member-popover-timeout-badge-readonly-desktop.png` (permissions: `Perm.kickMembers`, target already timed out, no shared call).
  Fix: compute `canOfferTimeoutChips = canTimeOut && profile.timedOutUntil == null` and fold that into `showModeration` in place of the bare `canTimeOut`, the same way `canEject` already folds in `inCallTogether`.
  Severity: high (a real, reachable permission combination, not a hypothetical one; rated medium by the UX pass on the grounds that it reads as "half-loaded" rather than "broken," high by the frontend pass on the grounds that the section header is unconditionally wrong for this combination).

- **The timeout badge's summary omits the one bit that is deliberately spared.**
  "Can read, can't post or join voice." accurately covers `TIMEOUT_DENY` (`store/timeouts.rs:41-45`: SEND_MESSAGES, ADD_REACTIONS, ATTACH_FILES, CONNECT, SPEAK removed, VIEW_CHANNEL untouched), confirmed against the server's own bit list.
  CLAUDE.md's canvas notes record that `USE_CANVAS` is deliberately spared by a timeout, so a timed-out member can still draw.
  The badge doesn't claim otherwise, but a moderator reading "can't post" has no reason to assume canvas ink is exempt, and it is.
  Fix: "Can read and draw on the canvas; can't send messages or join voice."
  Severity: low (cosmetic, not a broken affordance; the underlying enforcement is correct).

- Touch targets, block/unblock wording, and the read-only badge variant all check out.
  `AppButton`'s height floors at `AppSizes.rowTouch` (44) on a touch surface, so the compact "Lift" ghost button is not actually a sub-44px target on phone despite its compact desktop rendering.
  `member-popover-blocked-desktop.png` offers "Unblock" rather than "Block" again, avoiding the "did my block fail?" read.
  No finding on either.

## Member popover - Eject scope mismatch (permission-scope mismatch, site six)

Verdict: real, medium severity, and one of two sites in this document where the client asks the wrong permission scope - this codebase's fifth and sixth confirmed instance of the pattern (see Cross-cutting, and `shell.md`, `settings.md`, `voice.md`, `overlays.md` for the other five).

- `canEject` reads `mine.hasPermission(Perm.kickMembers)`, the caller's deployment-wide base permissions (`member_profile.dart:301-305`, `myPermissionsProvider` at `admin_providers.dart:24-28`).
  The server's voice-kick handler checks `KICK_MEMBERS` per channel instead: `permissions.contains(VIEW_CHANNEL.union(KICK_MEMBERS))` from `permissions_in_channel(ctx.user_id, channel_id)`, and its own escalation check reads `granted_permissions_in_channel` rather than `granted_base_permissions` for the stated reason (`http/voice.rs:303-350`: "a caller who holds `KICK_MEMBERS` only through a channel overwrite may still hold nothing deployment-wide").
  There is no channel-scoped permission provider anywhere in `client/packages/app/lib/src/providers/` to read the right value from.
- Confirmed against the harness: `member-popover-eject-desktop.png` and `member-popover-call-audio-only-desktop.png` are produced by toggling `myPermissionsProvider` alone (`ui_overlay_snapshot_moderation_test.dart:277-291`).
- Impact: a moderator granted `KICK_MEMBERS` only via a per-channel or voice-channel overwrite never sees "Eject from call..." at all, even though the server would honor the kick - a false negative that silently withholds a working action, the more serious direction here.
  Voice-channel-scoped `KICK_MEMBERS` overwrites are a real, supported feature (`channel_overwrites_screen.dart` exists for exactly this), so this is reachable in practice, not theoretical.
  The opposite direction (deployment-wide holder denied by a channel-specific overwrite) degrades gracefully into the same generic 403 the containment-gap case already uses.
- Fix: gate `canEject` on a per-channel permission read against `voice.channelId`, mirroring the server.
- Severity: medium.

## Member popover - admin-containment-gap

Verdict: the badge and callout are well placed and dismissible; the message inside them does not do the one job this scenario exists to test, and the server side is confirmed correct.

- **"Could not time this member out: you are not allowed to do that." never explains permission containment.**
  This is the app-wide generic `ForbiddenException` fallback (`api_failure.dart:22-23`), shared by every 403 in the product, not a message written for this screen.
  The server's `escalation_guard` (`http/escalation.rs:26`) genuinely refuses on "your granted permissions must contain the target's," called from `members.rs`'s `authorize` (`http/members.rs:266-280`) with `granted_base_permissions` compared on both sides, and the client never preflights this at all - it calls the API and shows whatever comes back.
  The 403 renders with no special containment wording; the test's own comment already says so ("there is no distinct wording for a containment gap").
  A moderator who does hold `KICK_MEMBERS` in general and still gets refused here has no way to learn why from the UI.
  The identical gap applies to "Remove from Space," which hits the same containment check.
  Fix: give timeout and removal a specific failure sentence naming the containment rule, e.g. "Could not time out Maya: she holds a permission your role doesn't have, so you can't act on her" - needs either a server-supplied reason string on this 403 or client-side special-casing for these two routes.
  Severity: medium.
- The rest of the card is good: nothing is disabled-and-silent, the moderator can see exactly what they tried, and the outlined danger-toned banner with a "Dismiss" affordance is the right shape.

## Member profile popover and its Remove-from-Space / Eject confirmations

Verdict: the popover screens themselves read well; the two confirmation dialogs behind "Remove from Space..." and "Eject from call..." are some of the most precise copy in the product, with one real gap and one real duplication risk.

- `member-profile-popover-desktop.png`/`-phone.png`: "Roles...", "Time out for...", "Remove from Space..." correctly use the ellipsis convention for "opens something further," danger tone is reserved for the one genuinely destructive item, and phone touch targets comfortably exceed 44px.
  No finding.
- Eject confirmation: "They will be disconnected from the call right now. Nothing stops them rejoining - time them out or remove them from the Space for something that sticks."
  States the limit of the action in the same sentence as the action.
  No finding.
- Remove confirmation: "They will be signed out and cannot sign in again, and any invites they handed out stop working. Everything they wrote stays, still shown as theirs. You can let them back in later."
  Its own inline comment says "remove misleads in both directions," exactly the right instinct.
- **The Remove-from-Space confirmation omits the one caveat CLAUDE.md itself flags as important: it does not stop a fresh account on an open Space.**
  "cannot sign in again" and "you can let them back in later" both read as a complete, moderator-controlled outcome, true on the default invite-only join policy and not true when `join_policy: open`.
  `deploy/README.md` already warns operators about exactly this; the in-product confirmation does not.
  Fix: append a conditional clause when the Space's join policy is open, e.g. "...This Space allows open sign-up, so nothing stops them registering again in the meantime."
  Severity: medium.
- **The Remove-from-Space confirmation copy is duplicated byte-for-byte in two files rather than shared.**
  `member_profile.dart`'s `_remove` (lines 256-266) and `report_card_actions.dart`'s `removeReportedAuthor` (lines 105-123) carry the identical confirmation title, body copy, and confirm label.
  Nothing has drifted yet, but this is the exact shape CLAUDE.md's own history warns about - two independent copies of one safety-action's copy, one edit (such as the open-join-policy fix above) away from disagreeing.
  Fix: lift the confirm-and-remove sequence into a shared helper, e.g. in `safety_actions.dart` or a new `moderation_actions.dart`, the same way report/block were unified, and have both call sites use it.
  Severity: medium.

## Report queue cards

Verdict: identity resolution (author/reporter/gone/resolving) is the standout of this set, four distinct honest states matching the server's real null semantics exactly, with no permission-tiered withholding to get wrong on the reporter side.
Two real gaps sit on top of that: an unlabeled reason, and a wrong permission scope on the one destructive action a card offers.

- **The report's own reason has no label, unlike everything else on the card.**
  `report_card_labels.dart`'s own doc comment states the design principle plainly: reporter and subject are labelled explicitly "rather than left to font weight and position to say which is which - that read as a byline, exactly backwards."
  That principle is applied to `ReportLabeledValue` for author/reporter and skipped for `report.reason`, which renders as unlabeled body text directly beneath the reported person's name (`report_card.dart:199`).
  In a message report (`report-card-message-full-actions-desktop.png`, `-jump-unreachable-desktop.png`) the reason sits immediately above the boxed message snapshot with no heading on either, and can read like the start of the quoted content rather than the filer's own explanation.
  In a user-kind report (`report-card-no-snapshot-desktop.png`, `report-card-reporter-anonymous-desktop.png`) there is no snapshot box at all, so the reason is the only prose on the card with nothing to mark it as "why."
  Fix: reuse `ReportLabeledValue(label: 'Reason', value: report.reason)` the same way author/reporter already do.
  Severity: medium-high (the exact ambiguity class this file already solved once, and the fix is nearly free).

- **`report.reason` is also styled with a raw `TextStyle` instead of the `AppText` scale.**
  `report_card.dart:199`: `Text(report.reason, style: TextStyle(color: tokens.textPrimary))`.
  Every sibling text on the card - `ReportLabeledValue`'s label/value, the reporter/timestamp row - uses an explicit `AppText.*` step.
  `AppText.body` sets `fontSize: 15, height: 1.45` as absolute literals rather than merging the ambient default, so a bare `TextStyle(color: ...)` falls back to whatever `DefaultTextStyle` supplies instead of the app's own reading style.
  The report reason, arguably the single most important sentence on the card, is the one piece of text not proven to be on the six-step scale.
  Fix: `AppText.body.copyWith(color: tokens.textPrimary)`.
  Severity: medium (design-system conformance drift, not visibly catastrophic in the current theme).

- **The reporter line and the author/subject line use different words for the identical "not yet fetched" state, and one does not read as loading at all.**
  `reporterLabel` (`report_card_labels.dart:56-60`) returns `'someone'` when the id has not resolved; `authorHeadline`/`subjectHeadline` (`report_card_labels.dart:69-77`) return `'Resolving...'` for the exact same condition.
  Confirmed live in `report-card-no-quick-actions-desktop.png` and `report-card-reporter-resolving-desktop.png`, both showing "Reported author: Resolving..." beside "Reporter someone" in the same card.
  `reporterLabel`'s own doc comment claims "an id not yet asked for reads as still loading," which `'someone'` does not communicate - it reads as a settled answer, the same register as "a deleted account" two lines below it, not as in-progress.
  Fix: give the reporter line its own `'Resolving...'` branch for the not-yet-fetched case, or correct the doc comment.
  Severity: medium.

- **"a deleted account" is used for two genuinely different situations: a reporter whose account has actually been deleted, and a reporter the server deliberately withheld as anonymous.**
  `reporterLabel`'s `id == null` branch (`report_card_labels.dart:57`) returns `'a deleted account'` regardless of why `id` is null.
  In `report-card-reporter-gone-desktop.png` that is correct.
  In `report-card-reporter-anonymous-desktop.png` the report was built with `reporterId: null` from the start - a reporter who may be an entirely active member whose identity policy hid them, not someone whose account is gone.
  The doc comment states this collapsing is deliberate ("read the same honest way"), but "a deleted account" is not honest for the anonymous case - it could lead a moderator to discount a report as unverifiable-because-gone rather than correctly-verified-but-withheld.
  Fix: a distinct string for the anonymous case, e.g. "a member (identity withheld)."
  Severity: medium.

- **A report naming the viewing moderator gives no reason for its missing actions.**
  `report-card-self-target-desktop.png` was built with full `kickMembers | banMembers` and still shows only "Jump to message," visually identical to a moderator with zero permission bits (`report-card-no-quick-actions-desktop.png`, modulo the profile-resolution state below).
  `report_card.dart:176,182-185` gates `canTimeOut`/`canRemove` on `!isSelf` with no visible trace of why, matching the server's own self-check in `members::authorize` (`http/members.rs:272-274`) - the gate itself is correct, only the silence around it is the finding.
  A moderator who knows they hold these bits and sees them vanish on one specific card cannot tell "you can't act on yourself" from "something is broken."
  Fix: a small caption under the Reporter/timestamp row when `isSelf`, e.g. "This report names you - you can't time yourself out or remove yourself."
  Severity: medium.

- **The disabled "Jump to message" gives no reason either.**
  `report-card-jump-unreachable-desktop.png` correctly renders Jump as present-but-disabled rather than absent, matching the project's own `AppSegmentedOption.disabled` precedent and the server's `jumpEnabled != true` gate (`report_card_quick_actions.dart:61-66`), but there is no tooltip or caption saying why - a deleted channel, an unviewable channel, or something else all read identically.
  `AppButton` has no `tooltip` parameter today (only `AppIconButton` does).
  Severity: low.

- **"Delete message" is gated on the wrong scope, and is a guaranteed dead button for a report about a DM message.**
  `canDeleteMessage = isMessageReport && mine.hasPermission(Perm.manageMessages)` (`report_card.dart:180-181`) reads deployment-wide permissions.
  The server's delete handler checks `MANAGE_MESSAGES` per channel: `has_permission(ctx.user_id, channel_id, MANAGE_MESSAGES)` (`http/messages.rs:255-259`).
  This is the sixth and seventh confirmed site of the permission-scope-mismatch pattern found across this whole review (see `shell.md`, `settings.md`, `voice.md`, `overlays.md` for the other five), and the most consequential one in the set.
  For a DM channel, `evaluate_channel_permissions` skips the role/overwrite model entirely and returns only `dm_permissions`'s `DM_BASE`/`DM_BASE.remove(BLOCKED_DENY)` (`store/permissions.rs:319-332`, `store/dms.rs:34-58`), which never contains `MANAGE_MESSAGES` for anyone - not even an ADMINISTRATOR, since the DM branch deliberately skips the ADMINISTRATOR bypass too.
  A DM message report is a real, reachable queue item by design (CLAUDE.md's "Moderation reaching only the channel kind it was written for" fix made exactly this visible), so a moderator opening a report about DM harassment sees "Delete message" as an available, enabled action, and every tap 403s.
  It is offered as present rather than absent for a permission the caller structurally cannot have, on exactly the report class - DM harassment - the codebase went out of its way to make visible to deployment-wide moderators in the first place.
  No screenshot or test in the suite covers this combination; `ui_overlay_snapshot_reports_test.dart` only exercises a `kind: text` channel fixture.
  Fix: resolve `MANAGE_MESSAGES` per `report.channelId` (mirroring the server), and additionally treat a DM channel kind as "delete never offered," the same special-case the composer and context menu already apply to DMs elsewhere.
  Severity: high.

- `report-card-author-gone-desktop.png` ("Author no longer on this Space"), `report-card-reporter-gone-desktop.png` ("a deleted account"), and `report-card-no-quick-actions-desktop.png` ("Resolving...") render correctly distinct for the subject/author axis; the only overlap is on the reporter axis noted above.
  `report-card-no-snapshot-desktop.png` correctly omits Jump/Delete for a user-kind report while still offering Timeout chips.
  Report queue visibility itself is correctly per-channel: `hidden_channels`/`report_visible_in` (`http/reports.rs:137-183,245-264`) filter in the `WHERE` clause before the page limit, resolve a thread to its parent, and keep a DM report visible to a deployment-wide `MANAGE_MESSAGES` holder.
  No finding on any of the above.

## Report dialog

Verdict: tone is right, plain, no hype, promises nothing the project doesn't keep, but it says nothing about what happens after "Report" is pressed.

- **No line tells the reporter what filing this actually does.**
  The dialog is title, textarea, character count, Cancel/Report, and never says who sees this or whether the reported person is told (they are not, by design).
  The silence correctly avoids inventing an SLA the project doesn't have, but it leaves the natural anxious question - "will they find out I reported them?" - unanswered at the moment it matters most.
  Fix: one caption line beneath the textarea, e.g. "Goes to whoever can review reports in this Space. The person you're reporting is never told who filed it."
  Severity: medium.
- Submit is genuinely disabled until text is entered (`_canSubmit = _controller.text.trim().isNotEmpty`), matching the server's required-reason rule, and the 0/2000 counter exactly matches `MAX_REASON_CHARS = 2000` (`http/safety.rs:27`).
  Phone touch targets are comfortably over 44px.
  No finding on either.

## Blocked-DM notices

Verdict: the "invisible" half genuinely leaks nothing about a block existing at the composer level, and the two lenses disagree about the failed-send screenshot in a way worth preserving rather than resolving.

- `dm-blocked-by-me-notice-desktop.png`, `-error-desktop.png`: match `blocked_dm_notice.dart` verbatim, plain and correctly scoped copy, routed through `GuardedActionState`/`AppErrorState` rather than a `SnackBar`, consistent with `run_guarded.dart`'s own documented distinction.
  No finding.
- `dm-blocked-by-them-invisible-composer-normal-desktop.png`: confirmed the composer has nothing block-aware in it at all - `blocksProvider` only ever contains ids this account itself blocked, so a block placed by the other party is structurally invisible client-side until a send is attempted.
  No finding.
- **Disputed: whether `dm-blocked-by-them-invisible-failed-send-desktop.png` leaks that a block exists.**
  The UX lens verified the screenshot against its own test fixture and found the failed-send state uses the literal generic string `'Could not send that message.'` with the same Retry/Discard row every ordinary network failure gets - no tell in color, icon, or copy, and read this as the non-leaking design holding, with no finding.
  The backend lens traced the same screenshot's text to a hand-authored fixture (`ui_overlay_snapshot_blocking_test.dart:214`, `failureReason: 'Could not send that message.'`) and found it does not match what the real send path produces.
  The real path is `sendOptimistically` -> `describeApiFailure('send the message', e)` (`channel_message_actions.dart:90-94`), which for the `ForbiddenException` a blocked-send 403 actually raises renders "Could not send the message: you are not allowed to do that." - distinguishable from a genuine `TransportException` ("the server could not be reached") or `RateLimitedException`, and different from the fixture's generic string.
  This contradicts the test's own docstring claim that the row is "byte-for-byte what any other failed send looks like" and the module doc's claim of being "indistinguishable from any other failed send" (same file, lines 6-7 and 194-197).
  Both lenses agree on one thing once this is accounted for: within an open DM, `SEND_MESSAGES` can only be denied by `BLOCKED_DENY` or `TIMEOUT_DENY` (`store/dms.rs:285-316`, `store/permissions.rs:223-232`), and both produce the identical generic Forbidden wording, so the real text does not uniquely identify "you are blocked" versus "you are timed out" even though it differs from a network failure.
  The finding both lenses converge on, stated plainly: the fixture not matching real output means the screenshot cannot actually answer the question it was captured to answer, so "does the failed-send state leak a block" remains unverified by this artifact regardless of which reading of the leak question is right.
  Fix: either make the fixture match real `describeApiFailure` output so the screenshot and docstring stop overclaiming, or, if true indistinguishability from an ordinary send failure is the actual design goal, special-case a DM-channel `ForbiddenException` on send to reuse the plain generic wording a transport failure gets.
  Severity: low-medium (not a confirmed security leak, but a genuine mismatch between what the code does and what the test/module doc claims it does, on the single highest-stakes screen in this review).

## Safety notices

Verdict: all four states (missing report, missing block, missing both, unknown) match `ServerSafetyNotice`/`_missingMessage` (`server_notice.dart:62-83`) exactly, driven by real capability-probe answers rather than a guess.
The capability names and pairing mirror the server's `Capability::ALL`/`wire_name()` (`http/capability.rs:26-36`), the probe distinguishes `POST /reports` (intake) from `GET /reports` (queue) so a deployment cannot fool it by keeping one and dropping the other, and `capabilities: null` (a pre-0.17.0 server) correctly renders as "too old to say" rather than an accusation.
Honest about the limitation, explicitly non-blocking ("You can still join"), and the missing-vs-unknown distinction carries its own icon rather than leaning on color alone.
No finding.

## Cross-cutting

- **The empty "MODERATION" header was found independently by two lenses reading the same evidence from different directions**, the frontend pass re-deriving the four gates from the harness and the UX pass reading the rendered screenshot cold; both land on the identical fix at `member_profile.dart:306-307`.
- **The permission-scope-mismatch pattern (client asks a deployment-wide provider for an action the server authorizes per channel) reaches its sixth and seventh confirmed sites in this document**, Eject (medium) and Delete-message-from-a-report (high); see `shell.md`, `settings.md`, `voice.md`, and `overlays.md` for the other five.
  There is no per-channel permission provider anywhere in `client/packages/app/lib/src/providers/`, so any future quick action that server-checks a channel-scoped bit should be treated as suspect until proven otherwise - a shape worth grepping for, not two isolated bugs.
- **The self-target, containment-gap, and jump-unreachable findings share one root cause worth fixing once.**
  A moderation action's absence or refusal reads identically today whether the cause is "no permission," "acting on yourself," "acting on someone your role doesn't cover," or "channel unreachable" - either the row is silently omitted or the refusal falls through to one generic 403 sentence.
  A single small "why this control isn't here" caption pattern, reused across the member popover, the report card, and any future moderation surface, would close all three with one shared component.
- **Two process findings, not defects.**
  `member-popover-plain-desktop.png`/`member-popover-blockable-desktop.png` and `report-card-no-quick-actions-desktop.png`/`report-card-reporter-resolving-desktop.png` are each byte-identical pairs (confirmed by md5sum), produced by separately-named `testWidgets` blocks that happen to build the same harness twice.
  Concretely, the "denied by permission" report-card state has never actually been verified separately from "still loading," since both existing tests pass no `profiles` map at all - a follow-up fixture supplying resolved profiles alongside empty permissions would close the gap.
  Separately, `member-popover-eject-desktop.png` and `member-popover-call-audio-only-desktop.png` render the avatar as an empty ring rather than the usual initials disc; traced to the snapshot harness's mock HTTP client answering the avatar fetch with `204` instead of the `404` a real server sends, which resolves to a zero-length image that fails to decode after the snapshot is written, rather than to the synchronous initials fallback a real 404 produces.
  Suspected fixture artifact, not a shippable defect; worth a one-line harness fix (return 404 for the avatar path) so a future reviewer does not chase it as a real rendering bug.
- **What held up, worth recording because this is the highest-stakes area in the product.**
  The blocked-DM composer genuinely shows nothing block-aware before a send is attempted, so there is no leak at the affordance level regardless of the failed-send copy dispute above.
  All four safety-notice states map onto real capability-probe answers, including the method-specific `POST`/`GET /reports` distinction and the honest "too old to say" fallback.
  Danger treatment is consistently outlined, never filled, across every screenshot reviewed (Block, Eject, Remove from Space, Delete message).
  Report and block remain a single shared implementation (`safety_actions.dart`'s `fileReport`/`blockUser`/`unblockUser`), called identically from every site that needs them, with no second divergence found on that specific pair.
  The admin-containment-gap's server-side enforcement is correct even where its client-facing message is not: the escalation guard genuinely compares granted permissions on both sides before the 403 is ever produced.
