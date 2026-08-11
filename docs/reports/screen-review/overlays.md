# Overlays review - merged

Three independent lenses (frontend implementation, UX/accessibility, backend/contract) reviewed the same screenshot set and code paths, merged here per screen or family.

## What this covers

Families: avatar-crop-sheet, camera-source-sheet/screen-source-sheet, channel-picker-sheet/role-picker-sheet/member-picker-sheet, member-roles-sheet, role-editor-sheet, create-channel-sheet/manage-channel-sheet, composer-actions-sheet, emoji-picker-sheet/space-emoji-sheet, pinned-messages-sheet, whats-new-sheet, command-palette, message-context-menu, canvas-object-context-menu, space-menu, and all eleven `confirm-*` families driven by `confirm_dialog.dart`.
Desktop and phone variants read where both exist, on the order of 50 individual PNGs.
Confirmation copy was checked against its real call site and against server behaviour, not just read as text.

## The short version

- ~~Two more sites join the systemic permission-scope mismatch already found in `shell.md`, `settings.md` and `voice.md`: the message context menu gates Delete/Pin on deployment-wide permissions where the server checks per channel, and the canvas object menu plus "Clear canvas" do the same with `MANAGE_CANVAS` - five instances of one root cause across four reports now.~~ Already closed on main before this pass (PR #523); see Cross-cutting below.
- ~~`confirm-eject-from-call` independently reconfirms the third instance already documented in `voice.md`'s cross-cutting section: still live in current source, same file, same gate.~~ Already closed on main before this pass (PR #523).
- ~~"Clear canvas" tells the user the action cannot be undone while the same client arms a working local undo for that exact act in the same breath.~~ Fixed 2026-08-10.
- ~~The command palette is the one overlay in this set that never adopted the shared `showAppSheet` split, and it overflows sideways at phone width instead of collapsing to a sheet.~~ The overflow is fixed 2026-08-10; it still does not go through `showAppSheet`.
- ~~The channel/role/member picker sheets and `member-roles-sheet` force a fixed height regardless of content, leaving most of the sheet empty for a two- or three-row list.~~ Fixed 2026-08-10.
- Everything else in this set - eleven confirmations, avatar crop, the source pickers, channel management, emoji, pinned messages, what's new - reads correctly and matches server behaviour line for line.

## confirm-* dialogs (11 families)

Verdict: the strongest, most consistent family in the whole overlay set, and the standard the rest of it should be measured against.

- Every confirmation goes through `confirmDangerousAction` (`client/packages/app/lib/src/widgets/confirm_dialog.dart:20`), which calls `showAppSheet`, so all eleven get the same phone/desktop split, the same card, and the same button row for free.
  A grep for `AlertDialog(` across `lib/src/` found zero raw dialogs and 16 `confirmDangerousAction` call sites (frontend).
- The danger action is always `AppButtonVariant.danger` (outlined, no fill, `button.dart:91-94`); cancel is always ghost, in a 50/50 `Expanded` split, on the left (frontend, UX).
- Every message states the consequence and names the target; every genuinely irreversible action carries "This cannot be undone," and `confirm-set-overwrite` correctly omits it since an overwrite can be replaced again (UX).
- Phone variants collapse to a real bottom sheet with a drag handle and `SafeArea`; desktop is a centred card; no clipping or overflow at the longest body text tried, three lines with embedded quotes on `confirm-set-overwrite` (frontend, UX).
- **Finding (low, evidenced): two call sites for the identical action use different titles.** `channel_message_actions.dart` (a message's own actions menu) says "Delete message?"; `report_card_actions.dart` (a moderator deleting a reported message) says "Delete this message?" - one word apart, same body copy, same consequence.
  Evidence: `confirm-delete-message-desktop.png` vs `confirm-delete-reported-message-desktop.png`.
  Fix: use one title everywhere delete-message appears (UX).
- The remaining nine families - delete-role, delete-category, delete-emoji, delete-message/delete-reported-message copy itself, dismiss-report, resolve-report, remove-from-space, revoke-invite, set-overwrite/clear-overwrite - were each checked claim-by-claim against the store and route behaviour they describe and all matched exactly, including several specific claims (invites revoked on removal, sign-in refused after removal, restore availability, no reopen route for a resolved report) verified line by line rather than assumed (backend).
  `set-overwrite`/`clear-overwrite` is also the one admin surface reviewed here where the client-side escalation guard is already correctly channel-scoped on both sides (`overwrites.rs:108,127-130,175,184-191` uses `permissions_in_channel`, not `base_permissions`) - the exception that shows what the other findings below should look like (backend).

## confirm-clear-canvas-one / confirm-clear-canvas-many

Verdict: the dialog's own "cannot be undone" claim is contradicted by the client's next action.

- ~~Both screenshots read: "This removes all N objects from the canvas for everyone in this channel. This cannot be undone." (`canvas_overflow_menu.dart:143-158`).~~
- `CanvasOpsController.clear()` (`canvas_ops_controller.dart:206-224`) submits the `clear` op and, on success, pushes `_pushUndo(_EraseEntry(result.op.id))`; `undo()` (same file, ~118-130) submits a `restore` op that un-deletes everything the clear just removed.
  This is real and server-backed, not cosmetic: `restore_candidates`'s clear branch matches on the clear op's own `deleted_at` fence, which is exactly the mechanism this project's own canvas-review history documents at length.
- So the confirming user is told the action is permanent, while the same client arms a working undo for it in the same breath - for as long as the pane stays open and the local 32-entry undo stack isn't superseded by 32 further actions.
  Evidence: `confirm-clear-canvas-one.png`, `confirm-clear-canvas-many.png` (backend).
- ~~Fix: soften the claim, e.g. "You can undo this immediately, but not after leaving the canvas," or drop "This cannot be undone" from this one dialog.~~
  Fixed 2026-08-10: the copy no longer claims permanence, and instead names the real Undo mechanism ("You can undo this with Undo until you close the canvas or take many more actions.").
- Severity: medium.
  Not exploitable, but a confirmation whose copy contradicts its own behaviour is worse than one that merely reads awkwardly - it can make a moderator second-guess a clear they actually meant, or trust a clear as final when it is not yet.

## confirm-eject-from-call

~~Verdict: dialog copy matches; the gate that decides whether the Eject row is offered at all is the same permission-scope bug already documented as the third instance in `voice.md`'s cross-cutting section, reconfirmed here from a different lens.~~
Already closed on main, not part of this change: see `voice.md`'s eject-button entry for the current source (`member_profile.dart`'s `canEject` reads `myChannelPermissionsProvider` now, PR #523).

- Copy is accurate: "They will be disconnected from the call right now. Nothing stops them rejoining - time them out or remove them from the Space for something that sticks." matches `voice.rs`'s `kick` handler exactly (removes the SFU participant only, does not touch `CONNECT`) (backend).
- ~~`canEject` (`member_profile.dart:301-305`) reads `mine.hasPermission(Perm.kickMembers)` from the deployment-wide `myPermissionsProvider`.
  The server's `kick` route checks `permissions_in_channel(ctx.user_id, channel_id).contains(KICK_MEMBERS)` (`voice.rs:325-339`), channel-scoped - `voice.rs`'s own doc comment says so explicitly.~~

## message-context-menu

~~Verdict: gates Delete/Pin/Reply/"Reply in thread" on the wrong permission scope; menu organisation and copy are otherwise the best in the set.~~
Already closed on main, not part of this change: `channel_screen.dart`'s `myPermissions` (fed into `messageActionsFor`) reads `myChannelPermissionsProvider(widget.channelId)` now ("site 1" per its own inline comment), part of the decision-0011 sweep, PR #523, landed before this pass started.

- ~~`messageActionsFor` (`channel_message_actions.dart:217-259`) computes `canDeleteMessage`, `canManageMessagePin` (MANAGE_MESSAGES) and `canReplyToMessage`/`canOpenThreadFor` (SEND_MESSAGES) from `myPermissionsProvider` - `GET /me` = `Store::base_permissions` (`http/users.rs:197`), deployment-wide, no channel overwrites.~~
- Otherwise the best-organised menu in the set: three tiers separated by dividers (reactions/reply, then copy/edit/pin, then report/block tinted-not-filled, then delete alone at the bottom), and the phone sheet shows the message being acted on above the menu (UX).
- Icons line up on a consistent leading column, labels don't wrap, danger items render in the danger text colour with no fill, and the phone variant correctly collapses to a bottom sheet with a drag handle - this is the sheet the picker sheets below should look like (frontend).

## canvas-object-context-menu / space-menu

~~Verdict: `canvas-object-context-menu` (and the canvas overflow's "Clear canvas" entry) has the same permission-scope bug as the message context menu; `space-menu` is clean.~~
Already closed on main, not part of this change: `canvas_pane.dart`'s `manageCanvas` reads `myChannelPermissionsProvider(widget.channelId)` now ("site 5" per its own inline comment), same PR #523. A separate, nearby site the same sweep missed - `canvas_pane_gestures.dart`'s `_onSelectStart`, which gates starting a select-drag on another member's object rather than the context menu or overflow item this finding names - was found independently in this pass and fixed the same way.

- ~~`canManage`, fed to `CanvasObjectContextMenu` and `CanvasOverflowMenu` from `canvas_pane.dart:369-370`, is `me?.permissions.hasPermission(Perm.manageCanvas)` - deployment-wide `base_permissions` again, same `meProvider`/`GET /me` source as above.~~
- `space-menu` itself is compact and clear, verbs describe the result ("Add channel", "Add category"), and its own creation items are correctly gated on `Perm.manageChannels`, which is genuinely deployment-wide on both sides - no mismatch there (backend, UX).
- Both menus are visually fine: consistent icon column, no wrapping, danger items correctly styled (frontend).

## avatar-crop-sheet

Verdict: the previously-shipped "buttons pushed off the bottom" bug is fixed at both viewports; a new, narrower rendering gap was found on desktop.

- The crop viewport is capped at `size.height * 0.5` and both buttons sit fully on screen at both viewports (frontend).
- Copy reads well: "Crop your picture" / "Drag to move, pinch to zoom" states the gesture up front, "Use picture" is correctly filled accent (this creates, it doesn't destroy), "Cancel" is plain text (UX).
- **Finding (medium, evidenced, root cause suspected): on the desktop capture, the cropped image itself never paints.**
  `avatar-crop-sheet-desktop.png` shows title, caption and both buttons but an empty circular viewport - no swatch, no error, no overflow.
  The phone capture, same 1x1 PNG fixture, renders correctly.
  Confirmed by cropping the desktop PNG directly: the region is flat `tokens.surfaceRaised`, nothing else.
  Suspected cause: the harness's `_viewports` map iterates desktop before phone with a fixed 350ms pump and no `pumpAndSettle` (`ui_overlay_snapshot_test.dart:159-160, 207-211`), consistent with a cold-image-decode race on first ever decode of the fixture bytes.
  Even if a harness artifact, `Image.memory(widget.bytes, ...)` (`avatar_crop_sheet.dart:103-108`) has no `frameBuilder`, so a slow decode of a real multi-megabyte phone photo can leave the viewport blank for a beat with nothing indicating a load is in progress.
  Fix: add a `frameBuilder` showing a spinner or the previous frame during first decode, and re-run with `pumpAndSettle` to confirm whether the blank is real (frontend).
- Severity: medium - likely cosmetic and fast in the common case, but it lands directly in the defect class ("sheet doesn't show what the user expects") this same file has shipped once before.

## camera-source-sheet / screen-source-sheet

Verdict: both fine at both viewports - title, rows, icons all present, no clipping.

- `screen-source-sheet` states the consequence up front ("Everyone in the call will see it until you stop sharing.") before listing choices, exactly the right place for that warning rather than burying it in a later confirm (UX).
- **Finding (low, duplication): the two files are near-byte-identical** (`camera_source_sheet.dart`, `screen_source_sheet.dart`), same `SafeArea` -> `Column` -> heading -> `AppListRow` loop, differing only in heading text, icon and one extra caption line.
  Worth collapsing into one parameterised `_DeviceChoiceSheet(title, caption, icon, items)`, the same near-copy pattern `member_roles_sheet.dart`'s own doc comment already flags elsewhere in this codebase (frontend).

## channel-picker-sheet / role-picker-sheet / member-picker-sheet / member-roles-sheet

Verdict: the weakest sheets in this review - functional, but missing the heading treatment their siblings have and forcing a fixed height regardless of content.

~~**Finding (medium, evidenced): no title/heading on any of the three pickers.**
  `ChannelPickerSheet.build` (`overwrite_target_picker_sheets.dart:34-46`) is a bare `ListView`; `RolePickerSheet`/`MemberPickerSheet` (lines 49-108) go straight from the sheet's top edge into rows.
  Every sibling "choose one" sheet in this set has a heading (camera-source-sheet says "Choose a camera", screen-source-sheet says "Share a screen"); these three don't.
  On desktop this reads as a floating, borderless pill hugging a single row rather than a modal - there is a real dialog card (`surfaceRaised` + `borderSubtle`), but with no title and no padding it visually collapses into the row's background.
  On phone, a person opening "set overwrite for a role" and seeing a bare list of role names has no on-screen confirmation this is a role picker rather than, say, a mention target.
  Evidence: `channel-picker-sheet-desktop.png`, `role-picker-sheet-desktop.png`, `role-picker-sheet-phone.png`, `member-picker-sheet-desktop.png`, `member-picker-sheet-phone.png`.
  Fix: add a one-line heading to each - "Choose a channel" / "Choose a role" / "Choose a member" - matching the pattern two files over, which also gives screen readers something to announce on open.
  Severity: medium: admin-only surface, but it is the entry point to a permission-affecting action, and the fix is one line (frontend, UX, found independently).~~
  Fixed 2026-08-10: each of the three now opens with a `Text('Choose a channel'/'a role'/'a member', style: AppText.heading)` above the list.
- ~~**Finding (high, evidenced): `RolePickerSheet` and `MemberPickerSheet` force a fixed height of `MediaQuery.of(context).size.height * 0.6`** (`overwrite_target_picker_sheets.dart:29,58-59,90-91`) regardless of row count.
  With the fixture's 2-3 rows, `role-picker-sheet-desktop.png` and `member-picker-sheet-desktop.png` show a card roughly 530pt tall with content in the top ~110pt and ~75% dead space below.
  On phone this is worse: `role-picker-sheet-phone.png` and `member-picker-sheet-phone.png` cover roughly 60% of screen height with three rows at the top and empty surface below - the inverse of the avatar-crop-sheet's previously-shipped "too tall for the window" bug, this time "too tall for too little content."
  `member_roles_sheet.dart:81-82` has the identical `height * 0.7` pattern, and `member-roles-sheet-desktop.png`/`-phone.png` show the same near-empty card with two role rows at the top.
  This is a real, everyday-reachable admin flow (`ChannelOverwritesScreen`'s target pickers, and `MemberRolesSheet` from the member popover), not an edge case.
  Fix: drop the fixed height fraction; wrap the list in a `ConstrainedBox(maxHeight: ...)` so the sheet grows to fit content up to a ceiling and shrinks below it - the shape `whats-new-sheet` already gets right for the opposite (variable, often-overflowing) case.
  Severity: high (frontend).~~
  Fixed 2026-08-10 in both files: a new `_PickerList` (`overwrite_target_picker_sheets.dart`) wraps its `ListView` in `ConstrainedBox(maxHeight: ...)` with `shrinkWrap: true`, and `member_roles_sheet.dart`'s own list does the same, so each grows to fit its rows up to the same ceiling rather than always claiming a fixed fraction.
- ~~**Finding (low, design-system conformance, not visible in current screenshots): `_PickerError` and `_PickerEmpty` (`overwrite_target_picker_sheets.dart:120-156`) use a raw `TextStyle(color: tokens.textSecondary)` instead of an `AppText.*` scale style, and `_PickerError`'s retry action is a bare Material `TextButton` rather than `AppButton(variant: AppButtonVariant.ghost)`.**
  These only render on a `rolesProvider`/`membersProvider` error, so they weren't captured in this screenshot set, but they are a real deviation from the type scale and shared button component the rest of these sheets use correctly (frontend).~~
  Fixed 2026-08-10 in the same rewrite: both now use `AppText.body.copyWith(color: tokens.textSecondary)` and `AppButton(variant: AppButtonVariant.ghost)`.
- Role/member matching throughout (`role_assign_sheet.dart`, `member_roles_sheet.dart`) is by `role.id`/`roleIds.contains(role.id)`, never by name - correct given role names are not unique in the schema (backend).

## role-editor-sheet

Verdict: the form itself is clear; the primary action is unreachable without scrolling past every permission toggle first.

- Grouped permission toggles with plain labels, a live name field, and disabled (dimmed) toggles for bits the caller doesn't hold rather than a control that silently 403s (UX).
- **Finding (medium, evidenced): the primary "Create role"/"Save changes" button is the last item inside the scrolling list of roughly 16 permission toggles, not a pinned footer.**
  The whole form - name field, all toggles and the submit `AppButton` - sits inside one `SingleChildScrollView` (`role_editor_sheet.dart`).
  On phone, `role-editor-sheet-phone.png` shows the title, name field and only about ten toggles before the viewport ends; "Create role" is several screens further down.
  `whats-new-sheet.dart` gets this right in the same codebase: content in `Expanded(child: SingleChildScrollView(...))`, the "Got it" `AppButton` outside that region and always on screen (`whats-new-sheet-phone.png`).
  Fix: apply the same shape - move the permission list into `Expanded`+`SingleChildScrollView` and keep the submit button (and any error state) pinned outside it.
  Severity: medium - this is a workflow admins repeat every time they create or edit a role, and the fix pattern already exists elsewhere in the same file tree (UX).
- The server's `grantable()` check (`http/roles.rs`) and the client's per-toggle `enabled:` check (`role_editor_sheet.dart:98,134-135`) both read the caller's deployment-wide `base_permissions` - the two sides agree on scope here, since role CRUD really is deployment-wide server-side, unlike the message/canvas/voice findings above (backend).

## create-channel-sheet / manage-channel-sheet

Verdict: both fine.
Clean phone/desktop pair, correctly muted disabled "Create channel" button on an empty name field, danger zone uses an outlined danger button under an explicit "DANGER ZONE" label well clear of "Save changes" (frontend, UX).
Both gated on deployment-wide `MANAGE_CHANNELS`/`Perm.manageChannels`, and the server's create/rename/delete/reorder routes are themselves deployment-wide (`base_permissions`, not `permissions_in_channel`) - no scope mismatch here, since there is no channel-scoped authority for the client to have missed (backend).

## composer-actions-sheet

Verdict: fine.
No title, unlike camera/screen-source-sheet, but this reads as a menu of independent actions rather than a "choose one of these" picker, so the omission is less jarring than on the three picker sheets above and is not flagged separately from that finding (frontend).

## emoji-picker-sheet / space-emoji-sheet

Verdict: both fine.
Color emoji render correctly at both viewports (this project has a documented Fedora monochrome-emoji bug elsewhere; not reproduced here).
Category tabs use Lucide icons, not emoji-as-chrome.
`space-emoji-sheet`'s empty state ("This Space has no custom emoji yet. Native emoji are on your keyboard.") is a good model for the rest of the app - states why it's empty and what to do instead - and is correctly sized, not another instance of the oversized-height problem above (frontend, UX).

## pinned-messages-sheet / whats-new-sheet

Verdict: both fine, and `whats-new-sheet` is the pattern the picker sheets and role-editor-sheet above should be adopting.

- `pinned-messages-sheet`'s empty state ("Nothing pinned yet.") is compact, correctly sized and plain (frontend, UX).
- `whats-new-sheet` uses `AppIcons.highlight` (a Lucide sparkle glyph), not a real emoji character, confirmed by reading source.
  Its `SizedBox(height: size.height * 0.6)` is the *correct* use of a fixed-height fraction contrasted against the picker sheets: content is wrapped in `Expanded` + `SingleChildScrollView` so it scrolls independently while "Got it" stays docked at the bottom at both viewports (frontend).
- **Finding (low, evidenced): `MAX_PINS_PER_CHANNEL = 200` is enforced at the write (`store/pins.rs:24`, a specific 400 message via `http/pins.rs:96-101`), but `pinned-messages-sheet` shows no count or "N/200" indicator anywhere.**
  Not dishonest - the server's own descriptive text does surface correctly when the cap is hit (`api_failure.dart:19`) - just silent until then.
  Severity: low (backend).

## command-palette

Verdict: on phone, the palette does not collapse to a bottom sheet at all, and its fixed width overflows the screen.

- ~~`openCommandPalette` (`command_palette.dart:32-49`) does not go through `showAppSheet`; it calls `showGeneralDialog` directly and renders `AppMenu(width: _paletteWidth)` where `_paletteWidth = 480` (`command_palette.dart:25,173-178`), and `AppMenu` hard-sets `Container(width: width)` with no responsive clamp (`menu.dart:52-53`).
  On the 390px-wide phone viewport, the 480-wide box overflows symmetrically by 45 logical px per side.
  Verified by pixel-scanning `command-palette-phone.png` at y=440: the menu's own border/background is already present at the leftmost sampled column with no rounded corner or margin, and reappears near the right physical edge the same way - both edges at or past the screen boundary.
  Visually this crops the leading edge of every row (the `#` glyph on the "general" row is visibly cut).~~
  Fixed 2026-08-10, the narrower of the two suggested fixes: `paletteWidth = math.min(_paletteWidth, MediaQuery.sizeOf(context).width - 2 * AppSpacing.s24)` is now what `AppMenu` receives, so the card clamps to the viewport rather than overflowing it. Not routed through `showAppSheet` - the palette still opens as a `showGeneralDialog`, unlike every sibling sheet; only the width is fixed.
- This is the only overlay in the set whose phone rendering visibly differs in kind, not just spacing, from every sibling: everything else - 18 other sheets, 11 confirmations, 3 menus - uses `showAppSheet` and either becomes a bottom sheet or is a small anchored menu that fits the viewport.
  `sheet.dart`'s own doc comment describes exactly this failure mode ("a bottom sheet pasted along the bottom... gets cut off") as the reason `showAppSheet` was built; the palette cuts off sideways instead of at the bottom.
- Severity: high - a keyboard-shortcut-and-search entry point reachable from any screen, and it would ship visibly broken on real phone-width hardware (frontend).
- Functionally the palette itself is correct: the search placeholder states scope up front, results are grouped with icons distinguishing text/voice/DM, the first row is pre-selected (UX), and message search reuses `channelSearchProvider`'s helper, dropping any hit from a blocked author the same way the channel transcript and search bar do (backend).

## Cross-cutting

~~**The permission-scope mismatch is now confirmed at five sites across four reports, not three.**~~
Already closed on main, not part of this change: [docs/decisions/0011-per-channel-permissions.md](../../decisions/0011-per-channel-permissions.md) (PR #523, see CLAUDE.md's "The client asked one permission question and the server answered a different one, in eight places," 2026-08-10) landed before this pass started and converted every site named below to a per-channel read.
Checked directly against current source rather than assumed stale from the report text: `channel_screen.dart`, `canvas_pane.dart` and `member_profile.dart` all now read `myChannelPermissionsProvider`, each with an inline comment naming its own numbered site.
One nearby site the same sweep missed - `canvas_pane_gestures.dart`'s `_onSelectStart`, gating a select-drag start on another member's object rather than a menu item - was found independently in this pass and fixed the same way; see canvas-object-context-menu above.
`shell.md`, `settings.md` and `voice.md` each already found one instance: a UI-side gate reading the caller's deployment-wide `base_permissions`/`myPermissionsProvider` where the server authorizes the same action through `permissions_in_channel`, which folds in channel overwrites and (for a DM) an entirely different evaluator.
This review adds two new sites - `message-context-menu` (MANAGE_MESSAGES/SEND_MESSAGES) and `canvas-object-context-menu` plus the canvas overflow's "Clear canvas" item (MANAGE_CANVAS) - and independently reconfirms `voice.md`'s eject-button finding from a different entry point (the confirmation dialog's own gate, same underlying `member_profile.dart:301-305`).
Every instance shares the same root cause and the same fix shape: read a per-channel permission the way the server does, not the deployment-wide bitmask off `GET /me`.
None of the five is a security hole - the server enforces correctly in every case - but each is a real affordance/action contract mismatch: a control shown that always 403s, or a control hidden that the server would have honoured.
Worth a project-wide grep for every remaining client call site of `myPermissionsProvider`/`meProvider.*permissions` outside the surfaces confirmed correctly deployment-wide on both sides here (roles CRUD, channel/category CRUD, invites, emoji) to find whether there is a sixth.

**What held up, worth recording because it is unusual.**
All eleven `confirm-*` families come from one shared `confirmDangerousAction` component, with zero hand-rolled `AlertDialog`s anywhere in the app.
Danger is outlined, never filled, in every single confirmation and every context menu checked, with no exceptions found.
Every picker sheet - channel, role, member - matches its selection by id, never by display name, which is correct given role names are not unique in this schema.
This is a genuinely consistent baseline the newer overlays (command palette, the three target pickers) fell short of, rather than the norm being inconsistency.

**One rasteriser artifact was correctly identified and excluded, not reported as a defect.**
The UX lens found a translucent focus/hover glow behind the single row in `channel-picker-sheet-desktop.png` rendering as a hard-edged flat rectangle, matched it to the same known offscreen-rasteriser limitation `voice.md`'s cross-cutting section documents for the call dock's shadow, and correctly declined to list it as a finding.
No emoji-as-chrome anywhere in this set: the one glyph that could be mistaken for one, next to "What's new," is `AppIcons.highlight`, a real Lucide icon confirmed by reading source rather than assumed from the render.
