# UX Plan Adversarial Review

Status: adversarial pre-implementation review of `ux.md`.
Scope: attacking the navigation, responsive layout, keyboard, context menu, haptics, motion, accessibility, onboarding, and voice/canvas entry decisions before any code is written.
Cross-checked against `BRIEF.md` and the sibling specialist reports it depends on: `flutter-client.md`, `voice-canvas.md`, `realtime-sync.md`, `security.md`, `backend.md`, `networking-relay.md`, `appstore.md`, `design-language.md`, `audio.md`, and `media.md`.
Findings are ordered most severe first.
Severity "critical" is reserved for a finding that would force a redesign of an already-decided structure, not merely an addition to it.

## 1. Sidebar live voice avatars conflict with the decided presence-scoping model (critical)

Target: the information-architecture decision that "voice channels show live participant avatars inline so users see who is already talking before joining."
`realtime-sync.md` decides presence is "broadcast only to users sharing a conversation," derived from live WS connections in the hub.
A user has not joined a voice channel yet when they are merely looking at it in the sidebar, so it is unresolved whether that user counts as "sharing" that channel for presence purposes.
If "sharing a conversation" is read narrowly (active participants only, the reading that matches the rest of that report's ephemeral, participant-scoped typing and presence design), the sidebar feature as specified cannot be built: a user cannot see who is talking in a channel until they are already in it, defeating the feature's own stated purpose.
If it is read broadly (broadcast to everyone who can see the channel, regardless of membership), that is a materially larger presence fan-out than the report ever budgets: on the official hosted instance, a client would subscribe to per-channel roster state for every visible channel in a server, not just the one it is viewing, a fan-out cost that scales with total channels times total voice participants server-wide.
Neither `ux.md` nor `realtime-sync.md` states which reading is intended, and the two documents cannot both be implemented as written without one of them changing.
Concrete failure mode: engineers build the sidebar against the narrow presence scope, ship a feature that only shows roster state for channels the user has already opened, and the "see who's talking before joining" pitch silently does not work exactly where it matters most, a channel the user has never opened.
Resolution: `ux.md` and `realtime-sync.md` need one shared, written definition of the presence broadcast boundary (channel-visibility-scoped, not conversation-membership-scoped) before this ships, with the resulting fan-out cost added to the performance budgets in `performance.md`.

## 2. Multi-server identity and connection cost is unaddressed (major)

Target: "the leftmost rail is both account switcher and community switcher... a plus icon to join another."
Because "one home server is one community" and the account model requires a fresh invite-created account per self-hosted server (`security.md`, `BRIEF.md`), a user who joins several friend-group servers, the exact self-hosting pattern the report's own rationale describes, accumulates a separate password, a separate identity keypair, and a separate push registration per server, with no password manager or SSO story addressed anywhere.
The report's own risk note ("users who want one backend to host multiple communities are unserved in v1") only covers one backend hosting many communities, the opposite axis from one user belonging to many backends, which the rail explicitly supports via repeated "join another" icons.
No document, including `realtime-sync.md`, `backend.md`, or `networking-relay.md`, specifies whether the client holds a persistent WebSocket to every joined server simultaneously to keep the "unified unread badge" live, or lazily connects and relies on relay wake events, leaving a real battery and network cost (N concurrent TLS connections and keepalives instead of one) completely unbudgeted.
A visible symptom of the same gap: the "first-time canvas use, per account not per session" coach marks reappear on every new server a user joins, because there is no persistent cross-server identity for "per account" to mean "once, ever," undermining the feature's own intent.
Resolution: specify a connection lifecycle policy for joined-but-inactive servers (lazy connect, relay-driven badge updates) and add a per-joined-server resource line to `performance.md`'s client budget table.

## 3. Haptic trigger names a mechanism the sync architecture explicitly rejected (major)

Target: the haptics decision lists "canvas authority claim" as a trigger for a light haptic impact.
`voice-canvas.md` explicitly designs no authority or locking system: conflicting edits resolve "last-write-wins by seq, with an advisory-only... broadcast hint," and the report states plainly "that hint is not server-enforced locking."
There is no "claim" event in this project's actual sync model for a client to receive a haptic from.
Concrete failure mode: an engineer implements a haptic for an event the server never emits, producing either dead code or, worse, a redundant client-side "claim" concept invented to give the haptic something to fire on, quietly reintroducing the locking model `voice-canvas.md` deliberately rejected.
Resolution: replace the trigger with one that exists in the decided architecture, most likely folding it into the already-listed "drag pickup and drop" trigger.

## 4. Voice and Canvas merge risks paying canvas cost on every voice call (major)

Target: "voice and canvas are one screen... mitigated by letting it collapse to a thin strip without leaving the call."
`voice-canvas.md`'s rendering architecture keeps a spatial-index query running every frame against the viewport, five render layers, and a decoded-bitmap cache resident for the duration the canvas is open.
"Collapse to a thin strip" is described only as a visual change; nothing in `ux.md` states whether collapsing actually stops the per-frame spatial-index query and layer compositing, or merely shrinks the widget on screen while the same work continues underneath.
Because most voice calls are conversational rather than drawing sessions, and because battery impact is an explicit first-class brief requirement, the default behavior of every voice call silently paying full canvas rendering cost, with no stated way to actually avoid it, is a real risk to the majority use case, not an edge case.
Resolution: define "collapse" as an actual unmount or suspend of the spatial-index and paint layers when no canvas objects are visible and no drawing tool is active, not just a resize, and add a voice-only steady-state battery/CPU budget distinct from the canvas-active budget in `performance.md`.

## 5. No settings or account-management surface is designed (major)

Target: the entire scope of `ux.md`, which covers navigation, channels, voice, and canvas, but never designs a settings or account area.
Three sibling reports assume such a surface exists: `appstore.md` requires an always-visible in-app "Delete Account" entry (Guideline 5.1.1(v)), `security.md` promises "an in-app device list where revoking a device kills its session," and `audio.md` recommends a per-channel mute and a join/leave sound threshold as "a notification-settings requirement."
None of these has a place in the rail, sidebar, or content-pane layout `ux.md` defines, and none is mentioned as a fourth destination alongside servers, channels, and voice.
Concrete failure mode: implementation reaches the point of building account deletion for an App Store submission and discovers there is no designed screen to put it in, forcing ad hoc placement under deadline pressure instead of a considered information architecture.
Resolution: add a settings/account information-architecture section to `ux.md` covering at minimum account deletion, device management, and notification preferences.

## 6. No administration or moderation dashboard is designed (major)

Target: the brief's explicit requirement for "excellent administration tools including user management, invite management, permissions, diagnostics, performance metrics, logging, moderation tools, health monitoring," matched by `backend.md`'s admin API surface and `performance.md`'s admin-facing metrics graphs.
`ux.md` never designs where or how an admin reaches any of this; the closest mention is a "setup checklist instead of a blank sidebar" for a brand-new server, which is not an admin console.
This is not a small gap given the brief calls administration tooling out as a first-class requirement on par with the chat experience itself.
Resolution: scope an admin-surface information architecture, even at a high level, in the same document that owns navigation for everything else.

## 7. Onboarding hides a real trust asymmetry behind "equally weighted" framing (major)

Target: "the cold-start screen presents three equally weighted entry points, join the official server, redeem an invite link or code, or connect to a self-hosted server by address."
`security.md` pins server identity via a fingerprint "embedded in the invite," a mechanism specific to the invite-link path.
Nothing in `ux.md` or `security.md` describes an equivalent fingerprint-verification step for "connect to a self-hosted server by address," which has no invite payload to carry a signed fingerprint, meaning that path is a blind trust-on-first-use connection with no user-facing verification moment at all.
Presenting all three entry points as visually and interactionally equal obscures that one of them is meaningfully weaker against a spoofed or typo-squatted server address, exactly the phishing scenario TOFU pinning exists to catch.
Resolution: give the manual-address path its own explicit fingerprint-confirmation step on first connect, and stop describing the three paths as equivalent in trust posture.

## 8. Invite redemption flow omits the mandatory terms-of-use step (major)

Target: the described redemption flow, "a confirmation screen showing the server's name, icon, and member count... then a display-name-and-password-only form."
`appstore.md` requires "a mandatory terms-of-use checkbox at invite redemption" to satisfy Google Play's 2026 UGC policy, and lists it as a required adjustment, not an option.
The flow `ux.md` describes has no step for it.
Concrete failure mode: the client ships built exactly to this UX spec, and Play Store review rejects the submission for a missing terms-acceptance step that a sibling report already flagged as mandatory.
Resolution: add the terms-of-use checkbox explicitly to the redemption flow in `ux.md` so it is not lost between two documents that were never reconciled against each other.

## 9. Global shortcuts are not achievable as global on the primary Linux target (major)

Target: "a global quick switcher (Ctrl+K)."
Fedora and GNOME Wayland are named as the primary Linux testing environment throughout the other reports, and under Wayland an application cannot register a true system-wide hotkey that fires while the window is unfocused without compositor-mediated portal support (`org.freedesktop.portal.GlobalShortcuts`), a materially different mechanism from X11's global key grabs and not guaranteed available or user-granted.
`ux.md` does not distinguish an in-app-focused shortcut, trivially remappable and conflict-free to implement, from a genuinely OS-global one, and calls the quick switcher "global" without qualifying which it means.
Concrete failure mode: a user expects Ctrl+K to summon the switcher from anywhere on their desktop, as the word "global" implies, and it silently does nothing unless the app window already has focus.
Resolution: scope the quick switcher explicitly as in-app-focused, or budget the Wayland portal integration work if true OS-global behavior is intended.

## 10. Zoom and pan limit haptic has no stated rate limit (minor)

Target: "hitting a zoom or pan limit" as a haptic trigger.
The same decision explicitly names "haptic fatigue" as the failure pattern being avoided, but nothing in the trigger list specifies a debounce or minimum interval between repeated firings.
Concrete failure mode: a user pinch-zooms past the maximum and holds, and the canvas fires a haptic impact on every frame it remains pinned at the limit, reproducing the exact fatigue pattern the decision was written to prevent.
Resolution: add an explicit debounce (for example, one impact per limit-hit, re-armed only after the gesture returns inside bounds) to the trigger definition.

## 11. Hover-ease duration disagrees with the design token it should reuse (minor)

Target: "every interactive element gets one hover token step plus a 120 to 150 millisecond ease."
`design-language.md`, authored the same day and feeding the same strategy document, defines `duration.fast` as a fixed 100 milliseconds for "press, hover."
The two reports specify two different numbers for the same interaction.
Resolution: `ux.md` should reference `duration.fast` by name rather than restating a numeric range that can drift out of sync with the actual token.

## 12. "Peek-and-pop" names a discontinued Apple API (minor)

Target: "on iOS this wraps the native long-press peek-and-pop pattern."
Peek and Pop was a 3D Touch-era interaction (`UIViewControllerPreviewing`), deprecated by Apple once 3D Touch hardware was discontinued starting with the iPhone XR, superseded by `UIContextMenuInteraction`'s long-press preview and menu, which is what current iOS apps actually use and what Apple's HIG documents today.
Concrete failure mode: an engineer implementing this section searches for or scaffolds against the named, deprecated API instead of the current one, or a reviewer familiar with modern iOS flags the terminology as wrong mid-implementation, costing time on a detail that should have been correct at the planning stage.
Resolution: rename the target as "the native long-press context-menu preview," matching `UIContextMenuInteraction`.

## 13. Android is treated as an afterthought in platform-specific decisions (minor)

Target: the context-menu section, which specifies iOS and Linux behavior but not Android's, and the transitions section, which folds Android into "Linux and Android Material shared-axis" without addressing Android's own predictive-back gesture system.
Android 14 and later increasingly expect apps to integrate with the OS-level predictive-back preview animation for in-app navigation stacks (channel drill-down, settings), a current, concrete platform requirement, not a hypothetical one, and it is not mentioned.
This is consistent with the rest of the plan's iOS-and-Linux-first sequencing, but since Android is a required brief platform, its absence from platform-specific interaction decisions should be an explicit deferral, not a silent gap.
Resolution: add an explicit "deferred, revisit in the Android phase" note for context menus and predictive back, rather than leaving Android's behavior undefined by omission.

## 14. Admin-issued reset code assumes an available admin (minor)

Target: the recommended default account-recovery mechanism, "an admin-issued one-time reset code."
The brief's own self-hosting target is "a handful of active users," typically run by a single hobbyist administrator, not a staffed support operation.
If that one administrator is unreachable, asleep, or has stopped maintaining the server, a locked-out user has no described fallback at all.
Resolution: note this as an accepted, disclosed limitation of self-hosted recovery, the same way the canvas accessibility gap is disclosed, rather than presenting the admin-issued code as a solved problem.

## A note on hidden complexity in the shared context menu

`SlimContextMenu` is asked to emulate three divergent native conventions, iOS's context-menu preview, Linux's GNOME-style cursor-positioned menu, and an unaddressed Android pattern, inside a single component.
This trades the ad hoc `showMenu` duplication the decision is written to avoid for a different kind of complexity: one abstraction that must correctly branch its rendering and gesture handling per platform internally.
That is not necessarily the wrong tradeoff, but the report presents it only as a clean win, with the "dumping ground" risk named only for scope creep, not for the cross-platform behavior-branching complexity the component itself concentrates in one place.

## Overall assessment

The plan is not meaningfully overbuilt for a small self-hosted instance; nearly every decision is runtime-cheap, and the one real combinatorial cost, the golden-test matrix across theme, viewport, and font-scale variants layered on top of `flutter-client.md`'s own golden-test plan, is a contributor-time and CI-time cost, not a resource cost paid by a self-hoster's server.
The more serious pattern across these findings is the opposite problem: several decisions were written against the echo-messenger reference or against an idealized architecture without being checked against this project's own sibling reports written the same day, producing a real, provable contradiction (finding 1), a dead reference to a rejected mechanism (finding 3), and two missing information architectures that other reports already assume exist (findings 5 and 6).
None of these invalidate the plan's core navigation and interaction model, but several need to be resolved, not just noted as risks, before implementation starts, particularly the presence-scope contradiction in finding 1 and the missing settings and admin surfaces in findings 5 and 6, since those are structural gaps other subsystems are already building against.
