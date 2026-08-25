# Desktop vs Mobile: how to build a responsive UI component

TLDR for anyone adding UI.
The full spec is the "Desktop vs Mobile" design doc; this is the short, actionable version kept in the repo so the rules travel with the code.
Its sibling `design-language.md` owns the visual tokens (color, type, spacing, motion); this file owns layout and which surface to use.

## The one rule

Layout responds to **window width, never to platform**.
A narrow desktop window and a phone render identically.
`Platform.isAndroid` / `Platform.isIOS` / `defaultTargetPlatform` must never decide layout or which surface to show.
One widget, a width-checked shell.
Platform checks are only ever for capability (push, tray, file pickers), never for shape.

## Three laws

1. Width decides, and it is re-checked live on resize (panes slide, they do not pop).
2. Pointer rows are 30-38dp; touch rows are >= 44dp.
3. Every hover affordance has a named long-press equivalent. A desktop-only action is a review defect.

## The three widths

- **compact** `< 600` - one pane, drill-down with a back action. `kCompactWidth` in `design_system/.../app_metrics.dart` is the single source (shared with hit targets so the two cannot drift).
- **medium** `600-1000` - adds the channel rail. Thresholds in `app/.../routing/breakpoints.dart`.
- **expanded** `>= 1000` - adds the member pane.

A resize crossing a threshold animates at 180ms.
On compact: back is `compact_channel_app_bar`, the rail becomes `channel_rail_drawer`, and members drill in from the channel header rather than a drawer.

## Which surface? Answer in order, stop at the first yes

1. **Actions on a thing the user just pointed at** (a message, a channel row, a canvas object) -> **context menu**. `AppMenu` via `context_menu_region.dart`, reached by right-click / kebab / long-press, anchored at the pointer. All three converge on one menu body.
2. **Picking one value for a control that stays on screen** (status, share quality, a role) -> **dropdown**: the same `AppMenu` body anchored to the control with the selected row marked. For 2-4 short options use a segmented row instead.
3. **Info about a thing plus its actions** (a member, an edit history, a pinned list) -> **popover / sheet**: an anchored popover on a pointer, a bottom sheet on touch. `showAppSheet` decides.
4. **A short task with a submit** (create channel, compose a poll, crop an avatar, confirm a destructive act) -> **`showAppSheet`**: a bottom sheet under 600, a centered dialog (max 460) above it. Never a raw `AlertDialog` or hand-rolled `showDialog`.
5. **A place with its own nav or list you return to** (settings, admin, member management) -> **`modalPage` route**: fullscreen on a phone, a floating ~860x720 panel on desktop. Sections inside are `SettingsPanes`, never their own dialogs.
6. **Status the user did not ask for** (offline, retrying, a degraded call) -> **banner**: it pushes content, never overlays it. Amber is transient; red attaches to what failed. Snackbars/toasts are for confirmations only, never for errors.

Write the rule number (1-6) in the PR description.
If none fits, the design question comes back to the spec before code is written.

## Never-rules

- Never a modal just to show a menu (use the anchored menu).
- Never a menu with more than ~8 rows (that is a sheet or a pane).
- Never a dropdown for 2-3 options (use a segmented row).
- Never nested modals (use an inline expander or a second step).
- Never a floating anchored surface under a thumb; never a sheet on desktop.
- Never a tooltip as the only carrier of information; never a tooltip on touch.
- Never a keyboard shortcut as the only path to a command.
- **Never a toast for an error.** Errors persist as an `AppErrorState` attached to what failed; a `check-error-surface.py` gate enforces this.

## Tie-breaker

- Dismisses on outside-click and loses nothing -> menu / popover.
- Dismissing would discard input -> a `showAppSheet` task with an explicit cancel.
- The user comes back to it -> a routed `modalPage`.

## Density: what moves with width and what never does

Tokens never change with width.
Colors, radii, the type scale and the spacing grid are identical at every width.
If a compact screen seems to need a new color or radius, the design is wrong, not the token set.

Only heights, hit targets and input font size move:

| Row | Height |
|-----|--------|
| `rowPointer` | 30 |
| menu row / `controlMd` | 34 |
| `rowTouch` (touch minimum) | 44 |
| touch menu / input | 48 |

The composer is h40 / font 14 on desktop (keyboard hints allowed) and h48 / font 16 on compact (font 16 blocks iOS auto-zoom; the send button is always visible).
Vertical rhythm is the only density lever: `rowGap` 4/8/12, grouped 1/2/4. Type, avatars and hit targets deliberately do not scale.

## The translation table

Every desktop affordance must state its compact equivalent, or it is not done.

| Desktop has | Compact must have | Never |
|-------------|-------------------|-------|
| hover reveal (kebab, action cluster) | long-press -> action sheet, same items | an action that silently vanishes |
| context menu / popover / modal | bottom sheet, handle, 44px rows | a floating anchored surface under a thumb |
| tooltip with a shortcut | a visible label, or nothing | tooltips on touch |
| keyboard shortcut (Cmd-K, R, E) | a reachable on-screen path to the same command | the shortcut as the only path |
| side pane (members, pins) | a drill-in route with back (180ms + 30% parallax) | overlay drawers that trap scroll |
| inline edit-in-place | the same, composer expanded to fit | a separate edit screen |
| drag to reorder | long-press lifts, same drop rules | reorder hidden behind an edit mode |

## The review question

For any UI change, ask: **resize the window across 600 - what appears, what converts, what dies?**
Anything that dies is the bug.

Reference widgets that already do this right, whose shape new UI should follow: `command_palette`, `channel_rail_drawer`, `compact_channel_app_bar`, `context_menu_region`, `showAppSheet`, `modal_page`.
