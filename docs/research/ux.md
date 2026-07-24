# UX and Information Architecture

Status: pre-implementation research, feeds into STRATEGY.md.
Scope: navigation, responsive behavior, keyboard navigation and command palette, context menus, haptics, onboarding and invite redemption, entering voice and the Voice Canvas, presence, settings, moderation, admin, and accessibility.
Derived from the brief and the owner's ten decisions, on first principles, against the decided stack: a single Rust plus Axum process for HTTP and WebSocket, embedded SQLite in WAL mode via sqlx behind a repository trait, a self-hosted LiveKit SFU for voice and screen share, and a Flutter client on Riverpod, Drift, and GoRouter.

## Navigation and information architecture

One deployment is one community, so the leftmost rail is both account switcher and community switcher.
Each icon is a joined deployment with an unread badge; a plus icon opens the join-or-connect flow.
The second pane is the channel and DM list: a recency-sorted Direct Messages section above categorized channels, with voice channels showing live participant avatars inline.
The third pane holds the message view or the Voice Canvas.
A fourth pane, members or a thread, is optional and collapses by default at narrower widths.
There is no unified cross-deployment inbox; every message stays attached to its community.

## Responsive behavior

Layout responds to available width, not platform, using compact, medium, and expanded breakpoints from the window's own size.
Compact shows one pane with stack-based drill-down and a back action.
Medium adds the channel list; expanded adds the member pane.
A resized window or a rotated tablet crosses these breakpoints live, with no relaunch and no operating-system branch.
Desktop-only affordances like hover previews get an explicit compact equivalent, typically a long press, rather than disappearing silently.

## Keyboard navigation and command palette

A global command palette is the primary keyboard entry point: it jumps to any channel, DM, or community, runs common actions, and opens settings.
Every list-like surface shares one arrow-key, Enter, and Escape convention.
Dedicated shortcuts move between channels and between communities on the rail.
Shortcuts are user-remappable from the start, since desktop window managers commonly reserve common combinations.
A cheat-sheet, reachable from the palette, keeps bindings discoverable.
Tab order and visible focus cover the whole shell; nothing in navigation or settings requires a pointer.
The Voice Canvas keeps its own keyboard contract, covered below.

## Custom context menus

One shared context-menu component backs every right-click or long-press surface: message rows, channel rows, member entries, and canvas objects.
It is keyboard-operable with arrows, Enter, and Escape, and its contents are scoped by permission, so unavailable actions are never shown at all.
On touch, the same menu opens from a long press as an anchored sheet rather than a separate touch-only system.

## Haptics

Haptic feedback marks a deliberate transition the user just caused: mute or deafen toggles, drag pickup and drop, a pan or zoom limit, or a confirmed destructive action.
An incoming message or event from someone else never vibrates the device directly; that is the operating system notification layer's job, keeping haptics rare and meaningful.

## Onboarding and invite redemption

The cold-start screen presents three equally weighted entry points: join the official server, redeem an invite link or code, or connect to a self-hosted server by address.
Self-hosting is first-class here, not a buried setting.
An invite link opens a confirmation showing the server's name, icon, and member count, then a display-name-and-password form with no email field and an optional, skippable profile-photo step.
A short human-typeable code gets its own entry screen.
Manual server-address connections add one extra step: confirming the server's identity fingerprint against a value the admin shared out of band, rather than trusting silently on first use.
A new server shows its admin a setup checklist instead of an empty sidebar; a new member sees pinned welcome content instead of a blank channel.

## Entering voice rooms and the Voice Canvas

Clicking a voice channel opens a preview first: roster, speaking indicators, mic and camera pre-toggles, and one explicit Join action, never an instant connection.
Once joined, voice and canvas are the same screen, with no separate step to open the canvas.
A persistent strip of avatars, speaking rings, and call controls stays visible, and can collapse the canvas to that strip without ending the call for a voice-only participant.
First-time canvas use, tracked per account, shows a couple of dismissible coach marks instead of a blocking tutorial.
One Leave Call action ends both voice and canvas together.

## Voice Canvas interaction contract

This is the one region permitted to draw on echo-messenger's canvas interaction lessons, since the brief names that project as inspiration for the feature.
A tool must be actively selected from a small, always-visible dock before a touch draws anything, so touch is unambiguously pan or draw, never both.
While the canvas holds focus, single-letter keys select tools, arrow keys nudge the selected object, and Escape clears selection, scoped tightly so it never bleeds into the shell's own shortcuts.
Any new gesture must declare its precedence against draw, pan, pinch, and double-tap before merging; ungoverned gesture additions are how a drawing surface becomes unpredictable.

## Presence visibility

Presence, meaning online and in-voice status, is visible only to users who share a channel with the subject, never broadcast globally across every community a person has joined.
In a large voice channel, the sidebar shows a summarized count and a handful of avatars rather than a live entry per participant, keeping broadcast cost proportional to what is visible.

## Settings, moderation, and admin

Personal settings cover profile, per-channel notification preferences, appearance, shortcut remapping, a linked-device list with per-device revoke, and account deletion, always explicit and reachable since self-hosted accounts have no other deletion path.
The same area explains recovery honestly: a locked-out user needs an admin-issued one-time reset code, since there is no recovery email in v1.
Moderation lives in the same shared context menu as everything else, with report and block on every message and member.
A report opens a short reason-and-context form and lands in a moderation queue, where each entry shows the content and an action set: dismiss, warn, remove, or act on the member.
Block is personal and immediate, hiding a user without requiring a moderator.
With no proactive content scanning, this reporting surface being easy to find is the primary safety mechanism.
A separate admin console covers members and roles, invites with usage tracking, the moderation queue, diagnostics, performance metrics over time, and an audit log.

## Accessibility

Accessibility is a first-class requirement against WCAG 2.1 AA, not a late pass.
Every interactive element carries a semantic label and role, verified in automated tests.
Text scales to 200 percent without clipped content, and touch and pointer targets meet a consistent minimum size across mobile and desktop.
Reduce-motion collapses decorative and chrome animation to instant changes or simple fades.
Direct-manipulation input such as canvas panning still tracks the pointer without added easing, since that is a response to a physical gesture, while app-initiated camera moves respect reduce-motion.
Keyboard operability extends everywhere except freehand drawing, which has no keyboard equivalent by nature.
The canvas instead offers a text-based activity log of who added or moved what and when, giving screen-reader users information access without false equivalence to spatial authorship.
