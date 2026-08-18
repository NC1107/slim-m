# Settings and administration

## What this covers

20 capture scenarios: personal settings and its 799/800 nav-rail boundary; Space settings in full-access, partial-access and no-access states, plus its own 799/800 boundary; the eight admin screens (roles, invites, channel overwrites, categories, emoji, reports, analytics plus its populated state, removed members plus its empty state); and the debug log plus its populated state.
Each was shot at desktop and phone-portrait widths in both themes, with the two breakpoint-boundary pairs shot on both sides of the boundary.
Reviewed independently from three angles: frontend (layout and design-system conformance), UX (copy, hierarchy, blank states, accessibility), and backend (does the client's permission gating match what the server actually enforces).

## The short version

- `space-settings-no-access` renders as a bare app bar over a blank white page with no explanation, found independently by the frontend and UX passes, and it is reachable not just by a stray URL but by a permission being revoked while the screen is already open.
- `admin-reports`' "Resolving..." placeholder collides with the same card's own "Resolve" button and silently swallows a failed profile fetch with no retry, a naming-collision problem and a missing-recovery-path problem that two lenses reached from opposite directions.
- The "Remove from Space" confirmation dialog never says it cannot stop the removed account from registering a fresh one and rejoining, the exact limitation CLAUDE.md records as this feature's defining constraint.
- Admin-overwrites' "Inherit" and "Clear" controls, both presented as always-safe, can silently un-deny a bit the caller doesn't hold themselves and 403 with no explanation the screen's own honest callout doesn't cover.
- Space settings' "Channel permissions" row is gated on the caller's deployment-wide MANAGE_ROLES, but the route it opens is gated per-channel, so the entry point can offer an action a channel overwrite will refuse.
- `debug-log` is the one settings screen that bypasses the shared `SettingsScreenScaffold`, so it loses the named back-button tooltip every sibling screen carries.

## Settings (personal, and the 799/800 boundary)

Verdict: clean across all three lenses.
The You / Calls / Safety / About grouping is legible, each row label says what it does rather than an internal name, and Sign out is visually and semantically separated by a danger-tinted icon.
The 799/800 nav-rail/detail-pane boundary collapses correctly in both directions with nothing clipped or stranded (`widgets/settings_panes.dart:106`, `_twoPaneFloor = 800`).
Backend confirms there is no admin surface in view on this screen, so nothing to check against a permission gate.
No findings.

## Space settings (full access, partial access, no access)

Verdict: the reachable states are correct and the gating matches the server row for row, but the no-access state is a literal blank frame, and one row's gate doesn't match the route it opens.

- **The no-access state renders nothing under the "Space settings" title: no card, no message, no explanation, found independently by the frontend and UX passes.**
  `SpaceSettingsSection` (`space_settings_section.dart:52-54`) returns `SizedBox.shrink()` when `spaceSettingsReachable(permissions)` is false, and that widget is the entire body of `SpaceSettingsScreen` (`space_settings_screen.dart:25`), wrapped only by the shared scaffold's app bar and padding.
  The file's own doc comment argues this is deliberate because the screen is "reachable only by a direct navigation, not by anything in the UI" - but that isn't the only path in: a member whose last gating permission is revoked while this screen is already open (a live role edit, an overwrite change, a demotion) watches it collapse to this same blank frame via `ref.watch(myPermissionsProvider)`, with nothing telling them why their moderation menu just vanished.
  Backend confirms there is no route-level inconsistency behind this - every one of the four gating bits is independently checked server-side by whichever screen would otherwise open - so this is purely a client presentation gap, not a security question.
  Evidence: `space-settings-no-access-desktop-light.png`, `space-settings-no-access-phone-portrait-light.png`.
  Severity: medium.
  Fix: render a short `AppCallout`/`AppErrorState`-style notice ("None of your roles grant access to anything here") instead of an empty body, matching the treatment every list-shaped empty state in this same area already gets.

- **"Channel permissions" is gated on the caller's deployment-wide MANAGE_ROLES, but the route it opens evaluates MANAGE_ROLES per channel, which a channel overwrite can deny even when the base bit is held.**
  `SpaceSettingsSection` gates the row on `permissions.hasPermission(Perm.manageRoles)`, the flat `GET /me` value (`space_settings_section.dart:100-105`), while `PUT/DELETE /channels/{channel_id}/overwrites/{kind}/{id}` is gated on `permissions_in_channel` evaluated for the specific target channel (`overwrites.rs:6-16,72-84`).
  A member who holds base MANAGE_ROLES but is denied it in one channel by an existing overwrite still sees and opens "Channel permissions," picks that channel, fills in the form, and gets a 403 on submit the entry point gave no hint of.
  The reverse case (granted only via a channel overwrite, not at base) under-offers instead, and is lower severity since it fails safe by simply not showing the row.
  Evidence: `space_settings_section.dart:100-105` vs. `overwrites.rs:74-84`.
  Severity: medium.
  Fix: either document this as inherent (no per-channel enumeration endpoint exists to preview it) in the row's own subtitle, or catch the specific 403 on submit and word it around the channel-specific denial rather than the screen's generic guarded-action error.

Full access and partial access both match the server one-for-one: Reports→manageMessages, Removed members→banMembers, Invites→createInvite, Who can join→manageServer, Roles→manageRoles, Channel categories→manageChannels, Emoji→manageServer, Analytics→manageServer, each confirmed against its own route's gate.
The 799/800 boundary for this screen is a single scrolling list by design and correctly has no two-pane state to collapse; identical rendering at both widths is correct, not a missed boundary.

## Admin: roles

Verdict: solid. One design-system nit.

- `roles_screen.dart:117` renders the role name with a raw `TextStyle(color: tokens.textPrimary)` instead of an `AppText` step, which bypasses the type-scale gate simply because it omits `fontSize:` rather than because it's on-scale.
  A 62-character role name still ellipsizes correctly at both 599 and 800px, so nothing is visually broken.
  Evidence: `admin-roles-compact-599-light.png`, `admin-roles-desktop-light.png`.
  Severity: low.
  Fix: `AppText.body.copyWith(color: tokens.textPrimary)`.

Everything else holds up across all three lenses: `@everyone` correctly has no delete/assign controls, delete confirmation copy states what happens and that it's irreversible, role matching is by id everywhere checked (`role_assign_sheet.dart:41`, `member_roles_sheet.dart:127`) with a doc comment calling out that names aren't unique, a permission toggle the caller doesn't hold is correctly dimmed to match the server's own `grantable()` check, and a last-administrator 409 is surfaced through `GuardedActionState`/`AppErrorState` rather than failing raw.

## Admin: invites

Verdict: solid. One design-system nit shared with admin-emoji.

- `invites_screen.dart:212,347` render the invite code with a raw `TextStyle(fontFamily: AppFonts.mono)` rather than extending an `AppText` step, the correct pattern already used two files over (`emoji_upload_card.dart:247-251`).
  This text silently tracks the ambient `DefaultTextStyle` rather than a named step and will drift from `AppText.code` the next time either changes.
  Severity: low.
  Fix: `AppText.code.copyWith(...)`.

Everything else matches: three invite states (fully used, active with a role grant, revoked) are each visually distinct, revoke is danger-outlined with honest irreversibility copy, and long codes/badges wrap and ellipsize cleanly at phone width.
Role-granting invites do have a full HTTP surface and a matching client picker that only offers roles the caller could actually grant; see Cross-cutting for the documentation correction this closes.

## Admin: channel overwrites

Verdict: the "no read-back, starts from Inherit, replaces everything at once" framing is honest and unhedged, which is the strongest disclosure in this whole review area - but one consequence of that same blindness goes undisclosed, and a sibling error state doesn't match its neighbours.

- **Selecting "Inherit," the default and never-dimmed state, is not unconditionally safe the way the screen implies, and the identical gap applies to the unconditional Clear button.**
  Server-side, `set`'s escalation check computes `granted = allow.remove(old_allow).union(old_deny.remove(deny))` and requires `caller_permissions.contains(granted)` (`overwrites.rs:113-124`).
  If the target already carries that bit *denied* from a prior overwrite - invisible to this screen by design - and the caller resubmits with it left at Inherit rather than re-selecting Deny, the request un-denies that bit, which server-side counts as a grant exactly like Allow does.
  If the caller doesn't hold that specific permission at their own base level, the entire "Set overwrite" call is refused with a generic 403, surfaced only as "could not set the overwrite."
  `PermissionOverwriteRow`'s own doc comment states plainly that "Deny carries no such check and is always offered" but says nothing about Inherit carrying the identical implicit cost.
  Clear has the same exposure server-side (`overwrites.rs:178-184`) with nothing client-side hinting it could fail for this reason.
  Severity: medium.
  Fix: extend the info callout to say plainly that leaving a permission at Inherit, or hitting Clear, can still be refused if the target was previously denied a bit the caller doesn't hold themselves - the screen can't show which bits that applies to, but it can say the risk exists.

- **The role/member picker sheets' error state doesn't match every sibling screen's error treatment.**
  `overwrite_target_picker_sheets.dart:138` (`_PickerError`) uses a raw Material `TextButton` and a raw `TextStyle`, hand-rolled with `Center`/`Column`, instead of the `AppErrorState(message:, onRetry:)` pattern every other "could not load X" case in this same directory uses (`roles_screen.dart`, `invites_screen.dart`, `emoji_screen.dart`, `categories_screen.dart`, `reports_screen.dart`).
  Not visible in the current screenshot set, since the fixture never triggers a load failure for these sheets - this is a source-only finding.
  A `TextButton` renders with Material's default colour rather than this app's accent/danger tokens, and the framing will look visually distinct from every other error state a moderator sees on this same feature surface.
  Severity: medium.
  Fix: replace with `AppErrorState(message: message, onRetry: onRetry)`.

Everything else here matches: MANAGE_ROLES-in-channel is the write gate on both sides, the Allow option is correctly dimmed to the caller's base permissions as a documented floor rather than the exact per-channel figure, and Administrator is correctly omitted from the editable list with a note explaining it bypasses overwrites entirely.

## Admin: categories

Verdict: no findings from any of the three lenses.
Long category names, the create row, rename-in-place with a confirm checkmark, and danger-outlined delete all render consistently at every width; the delete confirmation states plainly that channels fall back to uncategorised rather than being deleted; and gating matches MANAGE_CHANNELS on both sides.

## Admin: emoji

Verdict: no findings beyond the mono-`TextStyle` nit already covered under admin-invites (`emoji_screen.dart:122`, same fix).
"No emoji yet." reads as a plain accurate empty state rather than a failed load, the disabled Add-emoji button is correctly de-emphasised until both fields are filled, and viewing is open to any member server-side while upload/delete correctly stay behind MANAGE_SERVER on both sides.

## Admin: reports

Verdict: layout and paging both hold up, and the paging correctness in particular is a real strength - but two things in the same card mislead a moderator, and the destructive-action copy has one real gap.

- **"Resolving..." is a loading placeholder for an unfetched profile name, not a report-resolution status, and it collides with the two literal "Resolve" buttons on the same card - found from two directions.**
  The frontend pass flagged the naming collision: `report_card_labels.dart:69,80` (`subjectHeadline`/`authorHeadline`) return the string `'Resolving...'` while a profile hasn't come back from `batchProfilesControllerProvider`, rendered as a bold headline directly above an `AppButton(label: 'Resolve', ...)` (`report_card.dart:304-310`) and a confirm dialog titled "Resolve this report?" (`report_card.dart:116-121`) - a moderator skimming the card can easily read "Resolving..." as "this report is already being resolved" rather than "this name hasn't loaded yet."
  The UX pass reached the same card from the failure-handling side: `BatchProfilesController.resolve()` silently swallows a failed fetch ("Left unresolved; whoever asked can retry on the next build") and nothing in `report_card.dart` ever retries or offers a retry affordance, so a genuine fetch failure (network hiccup, server restart mid-load) leaves a moderator staring at "Resolving..." indefinitely on the one field that tells them who they're about to time out or remove, with no way to know it will never resolve.
  Evidence: `admin-reports-desktop-light.png`, `admin-reports-desktop-dark.png`, `admin-reports-phone-portrait-light.png`.
  Severity: medium.
  Fix: rename the placeholder to something that doesn't share a verb with the screen's primary action (e.g. "Loading..."), and distinguish "still loading" from "failed to load" so a genuine failure can render a retry affordance or fall back to the id rather than an indefinite "Resolving...".

- **The identical not-yet-fetched profile state is worded two different ways in the same card.**
  `reporterLabel` (`report_card_labels.dart:61`) renders the same `!profiles.containsKey(id)` condition as `'someone'`, while `subjectHeadline`/`authorHeadline` render it as `'Resolving...'`, both fed from the identical batch fetch (`report_card.dart:79-88`).
  Visible together in the second card in `admin-reports-phone-portrait-light.png` ("Reported author: Ada Lovelace" resolved, "Reporter someone" still pending).
  Severity: low.
  Fix: one shared wording for "not yet fetched," in the same change as the fix above since both live in the same 14-line file.

- **The "Remove from Space" confirmation dialog is honest about what the account can't do but silent about what it can't stop.**
  The dialog says the account "will be signed out and cannot sign in again, and any invites they handed out stop working," but never mentions that this doesn't stop the same person creating a brand-new account and rejoining - which CLAUDE.md itself records as the defining limitation of this feature ("nothing short of identity verification would" prevent it).
  A self-hoster reading "cannot sign in again" mid-resolution is likely to read this as a real ban rather than "this one account is blocked."
  Evidence: `admin-reports-desktop-light.png`, `admin-reports-desktop-dark.png`; source at `report_card_actions.dart:113-120` and the identical duplicate at `member_profile.dart:258-266`.
  Severity: medium.
  Fix: add one clause rather than restructuring the message, e.g. "This does not stop them creating a new account, especially if this Space is open to anyone with a link."

- Not flagged as a defect, noted for completeness: neither `canTimeOut` nor `canRemove` accounts for the server's granted-permission-set comparison (`members.rs:280-283`), so a moderator with the right bit but a narrower granted set than an administrator target sees the button and gets a 403.
  This is the same accept-and-surface-via-`AppErrorState` pattern used consistently everywhere else in this codebase, so it's listed as context rather than a gap.
  Severity: low.

Paging itself is correct and well-understood by its own implementation: a short page really does mean "queue exhausted for this caller" because the server excludes restricted channels before the `LIMIT`, and the client's own doc comment states that reasoning correctly.
Quick actions are each independently gated on the specific bit they need rather than the screen's blanket manageMessages gate, matching the server's own per-action authorization.

## Admin: analytics

Verdict: no findings, and the strongest screen in the set on the "does it imply it watches individuals" test, agreed by all three lenses.
The toggle's own copy is unhedged about what it counts and what it never does; the populated view defends against exactly the misreading the review brief warns about ("summed across every member"); every chart carries a visible text summary and a full-series semantics label so a chart is never the sole representation of its data; and the wire shape carries no `author_id`/`user_id` field at all, so there is nothing per-member to render even if the client wanted to.

## Admin: removed members

Verdict: mostly clean; one small placeholder gap.

- **A removal with no stated reason renders no reason line at all, rather than an explicit placeholder, sitting beside a card that does have one.**
  `removed_members_screen.dart:121` (`if (removal.reason != null) ...`) has no `else`, so the "Alan Turing" fixture card is two lines next to Grace Hopper's three, reading slightly like a rendering gap rather than a deliberate absence.
  Evidence: `admin-removed-members-desktop-light.png`.
  Severity: low.
  Fix: render a muted "No reason given." line when `removal.reason` is null, matching the "say what's true" pattern the empty-list state already uses.

Everything else matches: the empty state reads as a plain true statement rather than a failure, "Let back in" is correctly offered unconditionally since restoring can never itself create a last-administrator problem, and both states are gated on `banMembers` on both sides.

## Debug log

Verdict: entries render and expand correctly at every width and theme, but the screen breaks from its own family in two ways worth fixing.

- **`DebugLogScreen` builds its own raw `Scaffold`/`AppBar` instead of the shared `SettingsScreenScaffold` every other screen in this review area uses.**
  `debug_log_screen.dart:22-45` skips the frame that exists, per its own doc comment, because "eight screens carried this verbatim... that is not only duplication: it is eight chances for one screen to drift," despite this screen's route (`/settings/debug-log`) being registered as a settings screen.
  Two concrete consequences: the back button is a bare default rather than `BackToButton`'s named "Back to X" tooltip, a real accessibility regression today; and it bypasses `AppContentColumn`, so its content width has nothing tying it to its siblings if `modalPage`'s width constraint ever changes, a latent risk rather than a visible bug today.
  Severity: medium.
  Fix: route this screen through `SettingsScreenScaffold` like its eleven siblings.

- **Entry severity (error/warning/info) is conveyed by text colour alone.**
  Each row's category label ("flutter", "platform", "voice") is coloured by `DiagnosticSeverity`, but the label text is the source, not the severity - the same source can log at any severity depending on context - so there's no redundant text or icon cue distinguishing an error from a warning from an info line, the one place in this whole review area that encodes state by colour alone.
  Evidence: `debug-log-populated-desktop-light.png`, `debug-log-populated-desktop-dark.png`; source `debug_log_screen.dart:98-102` (`_levelColor`).
  Severity: low.
  Fix: a small leading severity glyph or a severity-word prefix ("ERROR flutter"), matching how `AppStatusDot` already pairs colour with shape elsewhere in this app.

- `debug_log_screen.dart:76`: the empty-state body text uses a raw `TextStyle(color: tokens.textSecondary)` sitting directly above a sibling line on line 83 that correctly uses `AppText.caption.copyWith(...)` for what reads as the same visual tier.
  Severity: low.
  Fix: `AppText.caption.copyWith(color: tokens.textSecondary)`.

- `debug_log_screen.dart:71`: `Icon(AppIcons.info, size: 28, ...)` uses a literal `28`, off the `AppSizes.icon*` scale (16/20/24/32).
  Severity: low.
  Fix: `AppSizes.icon24` or `AppSizes.icon32`.

The empty state copy itself reads well ("Nothing has gone wrong this session...", reassuring rather than alarming), and severity-colour mix, the `ExpansionTile` detail expansion, and copy/clear actions all render correctly across every width and theme tested.
Backend has nothing to check here: this is a purely local diagnostic capture with no server route involved.

## Cross-cutting

- **Documentation correction, not a screen finding. Since resolved: the claim below did not survive the PR #666 CLAUDE.md rewrite, so there is nothing left to correct. The pre-rewrite CLAUDE.md's claim that `POST /invites` "exposes `max_uses` and `expires_at` only" and that a role-granting invite "has no HTTP surface at all" is stale.**
  `CreateRequest.role_grant` has existed since PR #87 (`25b10fb6`), `resolve_grant` enforces the same no-escalation rule role assignment uses, and the client's `InviteRoleGrantPicker` already matches the server's `grantable` shape one-for-one.
  Update the entry in CLAUDE.md rather than treating this as still-open work.

- **The pattern behind the two blank-state findings is one root cause: a section with nothing to show renders as literal absence rather than a stated reason for the absence.**
  `space-settings-no-access` (`SizedBox.shrink()` for a whole screen body) and admin-removed-members' missing "No reason given." line (an omitted `Text` for one field) are the same shape at two different scales.
  Every list-shaped empty state in this review area already gets this right ("No emoji yet.", "Nobody has been removed from this Space.", "Nothing has gone wrong this session."); the gap is specifically the conditional-field and whole-screen cases that never got the same treatment.

- **A raw `TextStyle(color: tokens.textX)` with no `fontSize:` is pervasive across this review area**, not unique to any one screen: also seen in `permission_overwrite_row.dart:49`, `role_assign_sheet.dart:97`, `personal_status_sections.dart:112`, `personal_account_sections.dart:59,178`, and `role_editor_sheet.dart:186`, beyond the ones called out per-screen above.
  Because it omits an explicit `fontSize:`, none of these trip the type-scale gate, which only checks off-scale sizes, not the absence of an explicit step - worth a note for whoever next tightens that gate, since its real coverage is narrower than "every Text uses an AppText step."

- **The gate-then-surface-via-`AppErrorState` pattern is the strongest and most consistent thing across every admin screen reviewed: gate visibility on the caller's own base-permission bit matching the route's own gate, then treat any residual server-side refusal (escalation guards, last-administrator, per-channel overwrite denial) as an ordinary action failure rather than something the client tries to fully pre-compute.**
  That is a reasonable, consistently-applied trade-off, and the two real findings that fall short of it (space-settings' Channel permissions row, admin-overwrites' Inherit/Clear) do so only because the entry point itself, not just the final submit, is reachable under a false premise, or because the resulting 403 isn't explicable from anything shown on screen.

- **Destructive-action copy is otherwise the standout strength of this whole area.**
  Every irreversible admin action reviewed (delete role, revoke invite, delete category) states exactly what happens, to what, and that it cannot be undone, in plain non-hedged language, and every one is danger-outlined rather than danger-filled.
  Friction is correctly graded by reversibility rather than applied uniformly: a role delete or Space removal gets a confirmation dialog, a time-out (which lapses on its own) does not, and "Let back in" (a pure reversal) does not either.
  The one place this bar slips is "Remove from Space," covered above.

- **Role matching is by id everywhere checked in the admin surface, never by name.**
  Confirmed across roles, role-assign, member-roles-sheet, the invites role-grant picker, and overwrites' Allow-dimming - all use bitmask `.contains()`/`hasPermission()` semantics mirroring the server's own `caller.contains(requested)` shape, directly answering the "roles are not unique" question this review set out to check.

- **No emoji-as-chrome violations and no raw Material `ElevatedButton`/`Switch`/`Checkbox`/`ListTile` found anywhere in this review area**, the one exception being admin-overwrites' raw `TextButton` covered above.
