# Shell and messaging

## What this covers

The channel screen and its three empty/loading/offline states, the day divider, the desktop-narrow and tablet-portrait width variants, the thread panel in both its modal and full-screen presentations, the DM transcript and its in-call sub-variant, the not-yet-selected-a-channel placeholder, and the collapsed-rail reveal state.
74 screenshots back this report, reviewed independently from three angles: frontend (layout and design-system conformance), UX (copy, hierarchy, dead ends, accessibility), and backend (does the screen's claim match what the server actually does).

## The short version

- The DM message-action menu can offer Pin and Delete to an administrator inside any DM even though the server's DM permission model grants neither to anyone, a systemic client/server permission-gating gap that also reaches threads and was the exact DM-authorization question this review set out to check.
- A thread panel gives no orientation once you're inside it: no channel name, no parent message, just the word "Thread" - the single biggest orientation gap found in the whole shell pass.
- The icon that restores a collapsed channel rail is the sole way back and fails WCAG non-text contrast by roughly half the required ratio in both themes, measured directly from the rendered pixels.
- The composer's placeholder wraps to a second line at the exact width the two-pane rail-plus-content layout begins, found independently by the frontend and UX passes.
- A thread opened cold, by URL rather than by "Reply in thread," never gets its local read marker synced from the server, so the unread divider sits above the first message every session even though the server's own record is correct.
- Two smaller identity mix-ups: the DM header reuses the text-channel "#" glyph even though the code already branches on `isDm` two lines away, and the channel header truncates the channel's own name before its topic subtitle at the one width where both compete for space.

## Channel

Verdict: reads well at every width tested, with one width-dependent layout defect and one identity-hierarchy inversion, both real, reproducible, and confirmed against source.

- **Composer placeholder wraps to two lines at the exact width the two-pane rail-plus-content layout begins**, even though the identical text fits on one line at every other width tested.
  Found independently by frontend and UX: `channel-compact-599` (single pane, 599px) shows "Message #general" on one line; `channel-compact-600` (two-pane, 600px) wraps to "Message" / "#general," and the composer grows a full extra line for no content reason.
  The same wrap appears at `channel-phone-landscape`, where vertical space is already the scarcest thing on screen.
  Source: `widgets/composer_extras.dart:190-215` builds the hint as an unconstrained `Text.rich` with no `maxLines`/`overflow`.
  Evidence: `channel-compact-600-light.png`, `channel-phone-landscape-light.png` (compare `channel-compact-599-light.png`, `channel-expanded-999-light.png`, neither of which wraps).
  Severity: medium.
  Fix: cap the hint to one line (`maxLines: 1, overflow: TextOverflow.ellipsis`), or drop the `#channelName` suffix below a measured width threshold.

- **The channel header truncates the channel's own name before its topic subtitle, the wrong way round for which one carries identity.**
  In `widgets/channel_header.dart:77-104`, the name sits in a bare `Flexible` (implicit flex 1) while the topic sits in `Flexible(flex: 2)`, both racing for space in the same title row.
  At the width where rail, content and member pane are all shown at once (`channel-phone-landscape`, content pane roughly 367px), the topic gets double the pixel budget and the channel name truncates to four characters ("gene…") while the topic keeps substantially more text ("General chat f…").
  At wider two-pane widths with no member pane (`channel-compact-600`) only the topic clips, which is the expected and acceptable behaviour - it is specifically this three-pane width where the priority inverts.
  Evidence: `channel-phone-landscape-light.png`, header row crop.
  Severity: medium.
  Fix: give the name a higher flex weight than the topic, or an explicit minimum width, so the topic gives up space first.

Everything else checked out clean: the connection dot (offline/connecting/live) and the phone-only offline/connecting banner render distinctly and match `SpaceConnectionDot`/`RailConnectionBar`; the "you reacted" chip is distinguished by fill, border weight, and accent-coloured count rather than by hue alone; and unread state in the rail is dual-coded, bold channel name plus a dot, never colour alone.

## Channel: catching-up, genuinely-empty, offline-empty

Verdict: the three states are a genuine three-way distinction, not three labels sharing one signal, confirmed from all three lenses.

Catching-up shows a spinner and "Catching up on messages...", plus a neutral "Connecting" banner on phone.
Genuinely-empty shows the "Welcome to #name" start header with no banner.
Offline-empty shows "Offline. Messages will appear once reconnected." with no start header and an amber "Offline, retrying" banner on phone.
All three read correctly and collapse into none of the others (frontend, UX).
Backend confirms this is structural rather than conventional: `SyncStatus.offline | .connecting | .live` (`sync_controller.dart:22`) is a genuine three-value enum assigned only by `SyncController` itself, and `EmptyMessages` (`message_transcript_widgets.dart:249`) switches on that single value, so there is no way for two states to render as simultaneously true.
No changes suggested.
Worth protecting in any future copy pass: it would be easy to "simplify" these into one shared string later, and the distinction genuinely tells the reader whether to wait or act (UX).

## Channel: day divider

Verdict: renders correctly for what the fixture exercises; the fixture doesn't exercise the more interesting case.

The divider shows "July 27, 2025" once, above a single-day transcript, legibly in both densities and themes.
Backend confirms the gating condition is real, not a fixture coincidence: `isNewDay` (`message_transcript.dart:453-457`) reads `initialSyncCompleteProvider`, which this scenario deliberately overrides to true (`ui_snapshot_test.dart:176`) against the default-false every other `channel` scenario uses, demonstrating the documented purpose of stopping an optimistic send from briefly anchoring a divider it doesn't own.
What isn't exercised: whether the divider correctly breaks a same-author run across midnight, the case this project's own review brief calls out as the interesting one.
Not a bug in what's shown; the screenshot proves less than its name implies.
Severity: low, informational only.

## Channel: desktop-narrow, tablet-portrait

Verdict: clean at both widths and both themes, all three lenses in agreement.
Rail, transcript and member pane all fit without crowding at desktop-narrow.
At tablet-portrait the member pane correctly drops out (`LayoutClass.fitsMemberPane` returning false, `breakpoints.dart:46-55`), and the empty band above "Welcome to #general" is the transcript's normal bottom-anchored padding for a short conversation, not a defect.
No distinct backend interaction at either breakpoint beyond what "Channel" above already covers.

## Thread

Verdict: navigates correctly at both presentation modes and matches the server's intended chrome-suppression, but gives no orientation once you're inside it, and a cold open leaves the unread marker permanently wrong for the session.

- **The thread panel's header says only "Thread," with no channel name and no parent message shown anywhere.**
  A person who opens a thread from a busy channel, gets pulled away, and returns later, or opens one via a notification, has no way to tell which conversation or which original message this thread hangs off.
  There's no "Thread in #general," no quoted parent message, nothing but the two most recent replies and "There is more history above."
  On desktop the dimmed backdrop happens to show the parent channel's name behind the overlay, but that's incidental: it's gone by design at phone width, where the thread is the only thing on screen.
  Evidence: `thread-desktop-light.png`, `thread-phone-portrait-light.png`, `thread-expanded-999-light.png` (consistent across all variants checked).
  Severity: high - the single biggest orientation gap found across the whole shell pass.
  Fix: put the parent channel name in the header ("Thread in general"), and/or pin the message the thread was opened on above the transcript.

- **A thread opened cold, by URL rather than by "Reply in thread," never gets its local read marker hydrated from the server, so the "NEW" divider sits above the very first message every time the thread is reopened this session, regardless of what was actually read moments before.**
  `GET /channels` and `GET /dms` both structurally exclude a thread's channel row by design, and there is no `GET /channels/{id}` route at all.
  The only path that ever populates a thread's local `channels` row is `open_thread`'s own response, reached only via "Reply in thread"; `Event::ThreadUpdated` is handled only by the reply-count summary on the parent message, never by channel materialisation.
  A cold URL open therefore leaves the local row null.
  `MessageStore.setReadMarker` (`message_store.dart:405-414`) is a pure `UPDATE` that no-ops silently when the row doesn't exist, even though the server call in the same method succeeds and the server's own `read_states` row is written correctly (`store/read_state.rs:22-40`).
  `ChannelRefresher.refresh`, the only place that hydrates a channel's local read marker from the server, iterates only `listChannels()`/`listDirectMessages()`, which structurally exclude threads too, so even a full reconnect never corrects this.
  Net effect: `lastReadSeq` defaults to 0 (`channel_screen.dart:295`), so the unread-divider check places "NEW" above the first message on every cold open, a real and reproducible mismatch between what the server correctly recorded and what the client shows.
  Severity: medium - visible and incorrect, but session-scoped UI state only; no data loss, no security impact, and the server's own read state is correct throughout.
  Fix: have `ChannelScreen`/`ThreadScreen` upsert bare channel metadata on `isThread` mount before subscribing, the same upsert `openThreadFromMessage` already does, or make `setReadMarker` upsert rather than update-only for a thread channel id.

Everything else about the thread panel holds up: the desktop floating-modal presentation (clamped to 86% viewport height / 720px max, dimmed backdrop, `modal_page.dart:16-21,90-96`) and the full-screen phone presentation below 600px are both `modalPage`'s documented, deliberate behaviour, confirmed at `thread-compact-599`/`thread-compact-600`.
The composer hint correctly drops the `#channelName` suffix inside a thread.
`isThread` is correctly OR'd from the widget flag regardless of the local row's null state, so parent-channel chrome (pin, canvas, member toggle) stays withheld exactly as this project's earlier fix for the same scenario recorded.
The large empty space above "There is more history above." in the desktop modal is the same bottom-anchored transcript padding as the channel empty states, not a defect.
A thread also inherits the message-action permission-gating gap named in Cross-cutting, since a thread's effective permissions resolve to its parent channel's overwrites.

## DM

Verdict: transcript copy and layout read well and match the server for read state and blocking, but the header carries the wrong icon and the message-action menu can offer moderation actions the server will always refuse.

- **The context menu can offer Pin and Delete-another-participant's-message inside a DM to any account holding `MANAGE_MESSAGES`/`ADMINISTRATOR` at the deployment level, even though the server's DM permission model grants neither to anyone, unconditionally.**
  Full mechanism in Cross-cutting.
  Concretely: an administrator viewing their own DM would see "Pin" and "Delete" on the other participant's message, and both requests would 403 server-side.
  Not a security hole - the server independently re-authorizes and correctly refuses both - but a visible, reproducible "offered action that always fails" for exactly the account most likely to be testing the product day to day.
  Severity: high.

- **The DM header uses the same "#" hash glyph as a text channel** ("# Ada Lovelace"), even though the rail row for the same conversation correctly shows the person's avatar instead.
  `ChannelHeader` picks its leading icon with `isVoice ? AppIcons.voice : AppIcons.hash` and never branches on `isDm`, though the widget already receives and uses `isDm` for other decisions (hiding the member-list toggle) two lines away.
  A "#" reads as "public channel named after a person," the wrong signal for a private 1:1.
  Evidence: `dm-desktop-light.png`, `dm-normal-transcript-desktop-light.png`, `dm-desktop-dark.png`.
  Severity: medium.
  Fix: a person/contact icon for `isDm`, matching the branch that already exists two lines away.

- **`dm-call-phone-portrait`: the floating call-controls card's drop shadow is visibly clipped by the bottom of a short phone viewport**, rendering as a near-solid mid-grey band rather than fading out naturally.
  Verified by pixel-sampling the bottom row (solid `(118,119,119)`, absent on every other phone screenshot in this set); the control bar itself is not clipped or unreachable, only the shadow's tail.
  Evidence: `dm-call-phone-portrait-light.png`.
  Severity: low, cosmetic only.

Everything else matches: the DM start-of-conversation copy is clear and correctly distinct from a channel's welcome copy; read state correctly counts a blocked author's message toward the unread cursor the same way the server's own `unread_count` does, with no client/server divergence; and no rendered element implies extended access beyond the pair, since no member list or toggle shows for a DM at all.
`dm-normal-transcript` renders identically to `dm` in both themes and both viewports and carries the same findings; not repeated separately.

## No channel selected

Verdict: functionally correct and needs nothing from the server, but under-designed for what it is: the first thing a fresh desktop install shows.

- **The empty content pane is a single small line of grey text, "Pick a channel to start reading," centred with no icon and no next step offered - noticeably less than `channel-genuinely-empty` gets for what is, functionally, the same "nothing to show yet" situation.**
  That screen gets an icon, a heading, and a subtitle; this one does less to orient a new user despite being the very first screen a fresh desktop sign-in lands on.
  Evidence: `no-channel-selected-desktop-light.png` vs. `channel-genuinely-empty-desktop-light.png`.
  Severity: low/medium - not broken, just under-designed relative to its sibling empty state and its importance as a first-launch screen.
  Fix: give it equivalent visual weight and a copy change naming the actual next step, e.g. "Pick a channel from the left, or press Ctrl+K to jump to one."

Compact widths correctly skip this message entirely and show only the channel list; appropriate, no finding.
Backend confirms nothing here depends on a network request: the state renders before any channel is selected and needs no data fetch. Matches.

## Rail collapsed

Verdict: the collapse mechanism itself is correct at both widths and both themes, but the sole way back is close to invisible.

- **The restore-rail icon is a small, unlabelled outline sitting alone in a large empty field, and its contrast against the background fails WCAG non-text contrast by a wide margin.**
  Measured directly from the rendered pixels: light theme icon stroke `rgb(220,224,229)` against surface `rgb(247,248,249)` is 1.25:1; dark theme icon `rgb(46,51,58)` against surface `rgb(23,25,28)` is 1.38:1.
  WCAG 2.1 1.4.11 requires 3:1 for a UI component boundary, and this is the only control that reverses the collapse - there is no other affordance on screen once the rail is gone.
  This is the same class of problem this project's own history already fixed once for hairline borders, raising true black's hairline contrast; the same fix logic applies here.
  Evidence: `rail-collapsed-desktop-light.png`, `rail-collapsed-desktop-dark.png` (measured), `rail-collapsed-desktop-narrow-light.png`.
  Severity: high - not reliably discoverable even for a sighted user with reduced contrast sensitivity, and it's the sole path back to the full rail.
  Fix: raise the icon's stroke colour to meet 3:1 minimum in both themes, and consider a faint hover/pill background so the control has a hit-target boundary as well as a visible glyph.

Frontend confirms the collapse itself matches this project's documented fix: the reveal affordance is deliberately a small, undecorated two-bar icon with no decorated pill around it.
The two lenses disagree only on whether that restraint costs too much contrast, not on what was built - a real tension worth naming, since the documented design intent (undecorated, minimal) and the measured accessibility floor pull in opposite directions here, and the fix above (a stronger stroke colour, an optional hover pill) can satisfy both without contradicting the "no decorated pill at rest" intent.
Backend confirms this is a pure client-side layout toggle (`channelRailVisibleProvider`, a bare `StateProvider<bool>`) with no server interaction of its own. Matches.

## Cross-cutting

- **The client has no mechanism anywhere to read a per-channel effective permission, and this is the systemic cause behind the DM finding above.**
  `myPermissionsProvider` (`admin_providers.dart:28`) is the only permission source `channel_screen.dart` reads for message-level action gating (reply, open-thread, delete-another's-message, pin), and it is wired straight to `GET /me`'s `permissions` field, `Store::base_permissions`, a deployment-wide role/ADMINISTRATOR evaluation with no channel overwrite and no DM/thread special-casing applied at all.
  Confirmed by grepping the whole `client/packages/app` and `client/packages/api` trees for any per-channel permission fetch or computation: there is none.
  This is architecturally sound on the write side - every write is still re-authorized server-side from scratch regardless of what a caller can see, so nothing here is a privilege-escalation risk - but the read/display side has two distinct, concretely reproducible failure directions.
  Under-offering: a member granted `MANAGE_MESSAGES` only via a channel-specific overwrite never sees Pin/Delete in that channel, even though the server would accept the request; the admin-overwrites feature this product specifically ships to support "give this person moderation in this one channel" cannot be reflected in the message context menu at all today.
  Over-offering: a member holding `MANAGE_MESSAGES`/`ADMINISTRATOR` at the deployment level sees Pin/Delete offered in every channel regardless of a per-channel deny overwrite, and unconditionally inside every DM and every thread whose parent channel denies it; both end in an avoidable 403 for an action the UI itself offered, and this is what the DM finding above demonstrates concretely.
  None of the screenshots in this batch happen to expose the under-offering direction visually, since the seeded fixture channels carry no overwrites, which is why this reads as a DM-only bug rather than the general gap it actually is.
  Severity: high.
  Fix, in order of completeness: minimally, hide moderation-implying actions for `kind == 'dm'` and for thread messages scoped by a known parent-deny overwrite; more completely, add a per-channel effective-permission read the client can fetch or derive and thread that through in place of the deployment-wide value.

- **A capture-pipeline gap, not a product defect: reaction and thread-count glyphs briefly rendered as missing-character "tofu" boxes during this review, and that finding is retracted.**
  The UX pass first reported every reaction pill in the shell screenshots as unreadable ("▯2" instead of an emoji).
  The frontend pass re-checked against a freshly regenerated, settled capture batch and found full-colour emoji rendering correctly everywhere - the tofu boxes were an artifact of a mid-regeneration capture window on a shared box, a concurrent capture run had emptied and repopulated the image directory partway through this review, not a missing font fallback in the shipped client.
  Any screenshot taken before that regeneration shows the boxes; the settled batch this report's evidence citations point to does not.
  No product action needed here.
  Worth knowing for whoever reviews this app's screenshots again on a shared box: re-verify anything that looks like a font/glyph problem against a second, settled capture before reporting it, since the `AppFonts.emoji` fallback this project already shipped for Fedora rendering is in fact wired up correctly.

- **Message grouping (a run of one author collapsing into a block) is not visually verified anywhere in this capture set.**
  Every fixture transcript used across `channel` and `dm-normal-transcript` alternates authors on every message, so no screenshot exercises `AppDensity.groupedRowGap`.
  Not a bug; a gap in this fixture's coverage worth closing if the grouping behaviour is ever visually reviewed on its own.

- **Design-system conformance is clean across every screen in this area.**
  Every icon button is `AppIconButton`/`AppIcons`, every text style routes through `AppText`, and the only two raw `Colors.transparent` literals found (`message_row.dart:204`, `message_row_parts.dart:210`) are legitimate "no fill" sentinels rather than themed-colour literals.
  Rebuild scope also matches this project's documented no-Riverpod-in-the-render-loop rule: `MessageTranscript` is a plain `StreamBuilder`-driven `StatefulWidget` and `MessageRow` is a plain `StatelessWidget` with no per-row `ref.watch`, consistent with this project's own recorded history of hangs caused by exactly that pattern.

- **Nothing in this area carries unread, presence, connection state, or "you reacted" by colour alone.**
  Every status-bearing element also carries a shape, icon, or text difference, matching this project's own rule, checked consistently across every screen in scope.

- **The two highest-severity findings in this area share a shape worth keeping in mind:** a control or screen that is fine once you already know what it does, and confusing or invisible the first time you meet it.
  Thread's missing context and the collapsed-rail icon's contrast are both first-time-or-returning-after-a-while orientation gaps rather than functional breaks - worth remembering for whichever gets fixed first, since the same lens applies to both.
