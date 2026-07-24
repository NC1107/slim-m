# Product UX: Mobile and Desktop

Status: pre-implementation research, feeds into STRATEGY.md.
Scope: navigation, responsive behavior, keyboard shortcuts, context menus, haptics, hover states, transitions, accessibility, onboarding and invite redemption, and voice room and Voice Canvas entry.
This report builds on `flutter-client.md`, `voice-canvas.md`, `realtime-sync.md`, `security.md`, `backend.md`, and `media.md`, and treats the echo-messenger reference notes plus its `docs/voice-lounge/02-input-matrix.md` and `research/ui_ux_audit.md` as primary sources.

## Information architecture and navigation

Decision: one home server (one backend deployment) is one community, not a platform hosting many guilds.
The leftmost rail is therefore both account switcher and community switcher: each icon is a home server the user has joined, official or self-hosted, with a unified unread badge and a plus icon to join another.
The second pane is the channel sidebar: a collapsible Direct Messages section sorted by recency, then channels grouped into categories, with voice channels showing live participant avatars inline so users see who is already talking before joining.
The content pane holds messages or the Voice Canvas; an optional fourth pane (members or thread) collapses by default at narrower widths.
Rejected: Discord's one-account-many-guilds model, mismatched with a deployment that is itself the community, and a unified cross-server inbox, which hides which identity sent a message.
Risk: users who want one backend to host multiple communities are unserved in v1, an intentional cut revisited only if self-hosters ask for it.

## Responsive behavior

Decision: layout responds to available width, not platform, using Material's compact, medium, and expanded window-size classes already assumed by Flutter's adaptive tooling.
A GoRouter adaptive shell rebuilds the pane count from a `LayoutBuilder`, not `Platform.isX`, so a narrow Linux window snapped to half a screen collapses to the same single-pane stack a phone uses, and a landscape iPad gets the same multi-pane view a laptop gets.
Compact shows one pane with stack-based drill-down, medium shows sidebar plus content, expanded shows the full layout.
Rejected: branching on `Platform.isIOS`/`Platform.isLinux`, an anti-pattern that breaks the moment a window resizes or a tablet rotates.
Risk: desktop-only affordances like hover previews need an explicit compact-mode fallback, tracked per component.

## Keyboard navigation and shortcuts

Decision: a global quick switcher (Ctrl+K), Alt+Up/Down for channel navigation, Ctrl+Shift+Up/Down for server navigation, discoverable through an in-app cheat sheet (Ctrl+/).
Shortcuts are user-remappable from day one: GNOME and common Linux tiling window managers reserve many combinations, and Fedora is a primary testing target, so a fixed keymap guarantees conflicts.
The Voice Canvas keeps echo's Figma-style contract nearly unchanged: single-letter tool selection only while the canvas has focus, arrow keys nudge the selected object, Escape clears selection, and every new gesture must declare precedence against draw, pinch, and double-tap before merging.
Rejected: mouse-only canvas interaction, which fails the accessibility baseline below.
Risk: remapping adds a settings surface, mitigated by a versioned config validated at load.

## Custom context menus

Decision: one shared `SlimContextMenu` component for every right-click or long-press surface (message rows, channel rows, members, canvas objects), keyboard-operable with arrows, Enter, and Escape.
On iOS this wraps the native long-press peek-and-pop pattern; on Linux it opens a positioned menu at the cursor, matching GNOME convention.
Rejected: ad hoc `showMenu` calls per screen, the copy-paste pattern the reference project's own componentization rule warns against.
Risk: the shared component becomes a dumping ground if not curated, mitigated by a per-surface allowlist reviewed with the permission model.

## Haptics

Decision: haptics mark a deliberate state transition the user just caused, never a passively received event: canvas authority claim, mute and deafen toggles, drag pickup and drop, and hitting a zoom or pan limit get a light impact, while a message from someone else never vibrates the phone directly, since that is the OS notification system's job.
Rejected: haptic feedback on every send or receive, the single most common source of haptic fatigue in chat apps and a direct contradiction of the brief's understated direction.
Risk: under-using haptics can read as unresponsive, mitigated by testing the specific list above rather than adding triggers reflexively.

## Hover states and transitions

Decision: every interactive element gets one hover token step plus a 120 to 150 millisecond ease, and message-row actions reveal on hover rather than sitting always visible, matching the brief's clean direction.
Canvas object hover shows an outline immediately but a delayed 400 millisecond author tooltip, avoiding a flickery multi-cursor feel with several participants present.
Screen transitions follow platform idiom, iOS native slide-and-swipe-back, Linux and Android Material shared-axis, rather than one universal effect, since fighting a platform's expected back gesture is a common cross-platform complaint.
Direct-manipulation canvas gestures track the pointer with zero added easing; programmatic camera moves get a short eased transition, and everything collapses to fades under the OS reduce-motion setting.
Rejected: one custom transition curve everywhere, easier to build but foreign-feeling on both platforms.

## Accessibility baseline

Decision: every interactive widget carries a `Semantics` label, continuing the pattern the reference project's CLAUDE.md names as canonical, a 48 by 48 logical-pixel minimum tap target app-wide since it clears both iOS and Material guidelines with one number, and font scaling to 200 percent, verified by golden tests at 1x, 1.3x, and 2x added onto the multi-viewport goldens already planned in `flutter-client.md`.
Contrast is checked mechanically: every design-token pair is validated against WCAG AA in a small CI script, not manual review.
Screen reader testing covers VoiceOver on iOS and Orca on Linux, since Linux accessibility is routinely neglected and Fedora is a stated primary platform.
The Voice Canvas cannot be fully screen-reader-equivalent to a spatial drawing surface, so the honest commitment is a text-based "canvas activity" log, who drew or pasted what and when, reachable without opening the canvas.
Risk: the log gives information access but not equivalent authorship for screen reader users, a real, disclosed gap.

## Onboarding and invite redemption

Decision: the cold-start screen presents three equally weighted entry points, join the official server, redeem an invite link or code, or connect to a self-hosted server by address, rather than a generic sign-in form that buries self-hosting as an advanced option.
This matters for App Store review too: `backend.md` flags that Apple scrutinizes apps that only function paired with an undisclosed external service, so the self-hosted path must be first-class and described, not hidden.
An invite link opens a confirmation screen showing the server's name, icon, and member count, with the signed identity-key fingerprint from `security.md` in a collapsed disclosure, then a display-name-and-password-only form matching the brief's no-email-verification goal.
Short human-typeable codes get their own entry screen, and a new server shows the admin a setup checklist instead of a blank sidebar.
A new member sees a pinned welcome message instead of an empty conversation list, addressing the blank-screen churn echo's own audit measured as its top reason new users bounce.
Risk: self-hosted signup with no email means a lost password has no recovery path by default.
Recommend an admin-issued one-time reset code as the default recovery mechanism, with an optional recovery email left as a user choice, not a requirement.

## Entering and using voice rooms and the Voice Canvas

Decision: clicking a voice channel opens a preview state first, roster and speaking indicators with a single "Join Voice" button and mic and camera pre-toggles, never an instant connect.
Echo's own UI/UX audit independently flagged auto-join-on-click as a top interaction failure, so this is an evidence-backed fix, not a stylistic preference.
Once joined, voice and canvas are one screen: joining opens the canvas directly with a persistent, unobtrusive strip of avatars, speaking rings, and call controls, so there is no conscious switch between the call and the whiteboard.
A tool must be actively selected from a small always-visible dock before any touch draws, matching the gesture-state-machine contract in `voice-canvas.md`, so a touch is unambiguously pan or draw, never both.
First-time canvas use, per account not per session, shows two or three short dismissible coach marks rather than a blocking tutorial.
A single "Leave call" action ends both voice and canvas participation, while backgrounding the app keeps voice connected briefly inside the existing resume window rather than dropping it instantly.
Rejected: separate join-call and open-canvas steps, reintroducing the context-switch confusion the brief's AR-glasses framing is trying to avoid.
Risk: a voice-only user still pays the cost of the canvas layer being present, mitigated by letting it collapse to a thin strip without leaving the call.

## A wording flag

The brief and the Voice Canvas research both use "infinite" for the canvas, and the technical reports have already scoped that to a very large bounded world space, not true infinity.
The UX follow-on: keep that word out of in-app copy, since "infinite canvas" sets an expectation the product will eventually visibly violate, while "boundless workspace" describes the same experience without a promise the architecture cannot keep.
