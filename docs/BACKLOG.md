# Backlog

Status: accepted into backlog, not yet scheduled.
Date: 2026-07-23.
Source: the segment gap analysis in [design/feature-exploration.md](design/feature-exploration.md), approved by the owner.

These are agreed features and constraints beyond the v1 core.
None are scheduled yet.
The "Target phase" column is a tentative attachment point; the concrete phase numbers are reconciled into [ROADMAP.md](ROADMAP.md) after the architecture re-plan lands.
Nothing here overrides the founding principles: lightweight and cheap to self-host, one deployment is one community, performance first, and maintainability over feature accumulation.

## Accepted features

Each item is a real backlog entry with the segments that asked for it and a rough size.

| Feature | Segments | Size | Target phase (tentative) |
|---|---|---|---|
| Client-side voice controls: per-user volume mixer, voice-activity sensitivity, desktop push-to-talk | Gamers | M | Voice and screen share |
| Screen-share audio capture plus a quality and frame-rate toggle (desktop-first) | Gamers | M | Voice and screen share |
| Low-bandwidth and data-saver mode (audio-only calls, suppressed image auto-load) | Accessibility, gamers | M | Voice and screen share, client |
| Message editing with edit history | Teams | S | Client shell and text messaging |
| Pinned messages plus personal saved items | Teams, community | S | Client shell and text messaging |
| In-chat polls (native poll message type) | Community | S | Client shell and text messaging |
| Rich markdown and code blocks with a lean syntax highlighter | Teams | M | Client shell and text messaging |
| Advanced search operators (from:, in:, has:, before:/after:, filename:) | Power | M | Server and protocol core, client |
| Command palette and full keyboard navigation | Power, accessibility | M | Client shell and text messaging |
| Operator observability plus one-command backup, restore, and export CLI | Power | M | Administration and metrics, DevOps |
| Temporary member mute or timeout with auto-expiry | Community | S | Administration and moderation |
| Color-blind-safe redundant cues and an adjustable UI density setting | Accessibility | S | Foundations, design system |
| Webhooks, inbound and outbound, tightly scoped | Teams, power | M | Administration, extensibility |
| Tap-to-add: bring two phones together to swap an invite or open a DM | Community, owner idea | M | Client, after invites settle |

### Tap-to-add, in more detail

Owner idea, 2026-07-28: the NameDrop gesture, where two iPhones held together glow and swap a contact, but for adding someone to a Space or opening a DM.

The appeal is that it removes the worst part of the current flow. An invite today is a code somebody has to read out, paste, or screenshot, and a code in a screenshot is a code in someone's camera roll forever. A gesture that hands one over in person expires the whole problem.

What it cannot be is NameDrop itself. That is Apple's own contact-exchange flow and there is no public API to hook an app into it: the glow, the haptics and the sheet all belong to the system, and an app cannot register a payload for it.

So the honest options, cheapest first:

- **A QR code**, which works on every platform today, needs no entitlement, and is the thing people actually reach for. Show the invite as a QR, scan it to redeem. This is the one worth building, and it makes the rest optional.
- **AirDrop**, on iOS, by exporting the invite as a file or URL. Real, supported, and a share sheet away, but it is a share sheet rather than a gesture.
- **Nearby Interaction plus MultipeerConnectivity**, iOS to iOS, which can genuinely do "hold them together" with UWB ranging. This is the closest to the idea and by far the most work: a second transport, its own pairing and trust story, and a permission prompt. Android's equivalent is Nearby Share, and the two do not talk to each other.

The trap to avoid is building the third one first because it is the exciting one. A cross-platform QR covers the same need on every device the product ships to, and if the gesture ever lands it is a nicer front end onto the same invite code.

One thing to settle before any of it: an invite handed over in person should probably be single-use and short-lived by default, which is a different default from the link you paste into a group chat. `POST /invites` already takes `max_uses` and `expires_at`, so that is a client decision rather than a server change.

Priority note: push-to-talk, per-user volume, and device switching are close to mandatory for anyone arriving from Discord voice, and they are nearly free on the existing media stack, so they should ride with the voice phase rather than being treated as optional later polish.

## Architectural hooks to preserve

These are not features to build now.
They are cheap decisions to make correctly now so an expensive retrofit is never needed.
Every relevant phase must honor them.

- Accessible Voice Canvas (most important): the canvas is an addressable semantic scene graph of typed objects (position, size, content, author, z-order) exposed to the accessibility tree and drivable by keyboard, never a pointer-only immediate-mode surface. The current per-object canvas model already satisfies this; keep it a hard requirement so blind and motor-disabled users are never excluded from the signature feature.
- Threaded replies: reserve a nullable parent-message reference and keep unread aggregation groupable by a scope key, so threads can layer on later.
- Bot and automation identity: keep the RBAC principal model able to represent a non-human actor, and keep the outbound event envelope stable and versioned, so a future automation API builds on the webhook principal rather than needing an auth retrofit.
- Custom emoji and stickers: reserve a custom-emoji reference format in message content and reactions, and plan to reuse the content-addressed attachment store.
- Guest and restricted-visibility accounts: give invites a scope field and confirm the RBAC overrides can express see-only-channel-X.
- Scheduled messages: do not bake a created-equals-now assumption into every write path, so a deferred-send job can assign the snowflake id at publish time.
- Temporary and auto-created voice rooms: reserve channel lifecycle fields (ephemeral flag, creator, time-to-live).
- Live captions and transcription: reserve a per-speaker timestamped text event on the call channel, and ship speech-to-text only as an optional module, never required for a lightweight self-host.
- Simultaneous multi-server identity: keep the client data store and connection layer keyed by server and keep push registration per server and device, so multi-account stays a later client-only change that preserves one-deployment-one-community.
- Cross-instance import and portability: keep the export format stable and documented and lean on the reserved snowflake node-id space for conflict handling.
- Localization and right-to-left: route every user-facing string through an i18n layer from day one and use logical start and end layout, so RTL is a later flip rather than a rewrite.

## Deliberately out of scope

Recorded so they are not re-litigated.
Each can be revisited if the product's direction changes, but the default answer is no.

- Rich presence and game status: per-OS process detection and a maintained games database is a privacy and upkeep burden that drifts into Discord-clone territory.
- Soundboard for short audio clips: clip storage, call mixing, and upload moderation is non-essential ritual against the not-a-clone principle.
- Heavy machine-learning noise suppression: a native DSP or ML dependency adds CPU cost while gaming; enable WebRTC's built-in echo cancellation and basic noise filter instead.
- Client plugin or scripting system: a heavy maintenance and security surface with no viable sideloaded-code story under App Store rules; webhooks and the future bot API are the sanctioned path.
- Slash-command registration framework: Slack-app-platform scope creep; the command palette and webhooks cover the real need.
- Server-side link previews and URL unfurling: a lightweight self-host fetching arbitrary URLs can leak access to its internal network; only ever add as an opt-in, egress-sandboxed fetcher.
- Events with RSVP and a calendar subsystem: a real subsystem beyond chat; polls, pins, scheduled messages, and a webhook calendar integration cover the coordination need.
- Scheduled or recurring pings that store PII such as birthdays: recurring scheduler plus PII storage is bot-like scope creep that belongs in the automation API.
- Shared media gallery view: a non-essential convenience; because it is only a filtered query over the existing attachment store it can be added later at essentially zero design cost.

## From using it on a real device (2026-07-31)

Raised by the owner after real use, in his words where the wording matters.
Grouped by what they are rather than by where they were said, because three of them are the same underlying complaint about the message row.

### The message row

- ~~**Rows bounce on hover.**~~ Fixed in #251, released in client 0.18.0. The hover cluster is a `Positioned` child of a `Stack` in `MessageRow` now, so revealing it cannot reflow the transcript, and `message_row_hover_stability_test.dart` measures the row's height rather than inspecting the widget tree - asserting the button sits in a `Stack` would pass just as well if somebody put it back inside the `Column` within one.
  The original diagnosis, kept because the reasoning it replaced is worth not re-deriving: `ReactionsRow.build` need not re-find it: `ReactionsRow.build` (`client/packages/app/lib/src/widgets/message_row_parts.dart:83`) returns `SizedBox.shrink()` when a message has no reactions and is not hovered. Hovering therefore swaps absent-to-present rather than hidden-to-visible, and the row grows by the button's height, pushing everything below it.
  The current doc comment directly above that line argues for exactly this behaviour ("a permanent add-button under every message costs a row of vertical space each ... so the affordance belongs on hover with the row absent until then"). That reasoning is sound about the cost it names and is what produced the bounce, so the fix has to replace the argument rather than just the line: reserving the space instead would restore the very cost it avoids.
  The shape to copy is Discord's, which the owner named: a floating action cluster pinned top-right, in a `Stack`/`Positioned` inside `MessageRow` (the `builder: (context, hovered)` at `message_row.dart:144` already has the hover state), so it overlays rather than participating in layout. `ReactionsRow` then stops taking `showAddButton` entirely and renders only real reactions.
  Doing this also puts the affordance where the other two message-row items want to live, which is why these three should be one change rather than three.
- ~~**"as messages get long, the icons stay centered, they should align with the top of the text box like discord does"**~~ Settled 2026-07-31, and it turned out to be a third reading neither of the two below: the owner meant the **composer**'s own action icons, which sat centred against a growing input so they drifted down the screen as a message got longer. `composer.dart`'s action row is `CrossAxisAlignment.start` now. Released in client 0.18.0.
  The two readings that were recorded at the time, kept because the ambiguity is the point: this needed one word of clarification before anyone changes code, because the obvious reading does not survive checking.
  The *author avatar* is already top-aligned: `MessageRowLeading` (`client/packages/app/lib/src/widgets/message_row_identity.dart:109`) renders a fixed `_avatarSize` box, inside a `Row` that is already `crossAxisAlignment: CrossAxisAlignment.start` (`message_row.dart:181`). A long message does not centre it, so if that is what was meant, the bug is somewhere else and needs a screenshot.
  The likelier reading is the **hover action icons**, which is the same surface as the hover-reflow item above and would be fixed by the same overlay. Fixing that one is safe either way.
  Recorded rather than guessed at, because the two readings want opposite changes and shipping the wrong one is worse than asking.
- **No way to highlight a message.** No selection, no jump-to, no visual mark.

### Composing

- **No markdown or list formatting in any text field.** No way to type a list at all.
- ~~**Ctrl+V does not attach an image.**~~ Fixed in #256, released in client 0.18.0, and honestly bounded rather than claimed closed: Flutter's own `ClipboardData` carries only `text` and its source says plain text is the only supported variant, so there is no cross-platform clipboard image to read. The web build hooks the browser's `paste` event, which hands over the bytes and needs no permission prompt (unlike `navigator.clipboard.read`). On desktop and mobile the file picker is still the only route, and the what's-new entry says so rather than implying otherwise.

### The rail and DMs

- ~~**"Notes to self" is treated as a channel under the hood and should be a DM.**~~ Fixed in #256, released in client 0.18.0. It renders as an ordinary DM titled **You** now, with its own kebab menu carrying a hide action; hiding it is a local preference rather than a delete, and searching your own name brings it back, which the empty state says in words so the route back is discoverable rather than folklore.
- ~~**The DM section is wordy**~~ Fixed in #243.
- **No way to reorganise or move channels in the sidebar.** ~~and no way to collapse the left sidebar entirely~~ - the collapse half shipped in #256 (client 0.18.0). Reordering is still open, and note it is a full-stack question rather than a client one: nothing in the schema orders channels, so it needs either a `position` column and a route, or a deliberate decision that ordering is a per-device preference.

### Voice and canvas

- **The voice lobby screen has no purpose.** Owner's standing view, repeated: the join-preview screen is not earning its place.
- ~~**The pins button is styled differently from its neighbours**~~ Fixed in #242.
- **No background blur or replacement on camera**, which Discord has and which the owner calls "kindve a required feature" rather than a nice-to-have. Worth treating as a camera-launch blocker rather than polish: people will not turn a camera on in their own home without it. Note this is a real engineering item, not a setting - it needs a segmentation model running per frame on the local track before publish, so it lands with the camera work rather than after it.

### One open product question, not a task

The owner is thinking aloud about **canvas lifetime**, and it is not decided:

> perhaps if every docker server is just one "space" we could do a file browser or something, unsure how to handle canvases, like are they forever spaces, or is it like teams where every meeting is a new meeting and chat and the canvas changes after each meeting and is just an artifact or something, or should it persist for as long as the call exists, and people clear it as they need or save/export it as they need

Three candidate models, none chosen: a canvas that is permanent per channel (what ships today), one that is per-call and becomes an artifact afterwards, or one that lives as long as the call and is cleared or exported by hand.
This is a product decision with real schema consequences - `canvas_objects` is currently keyed per channel with no notion of a session - so it belongs in [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md) rather than being resolved by whoever picks up the next canvas slice.

### A second round, 2026-07-31

- ~~**A what's-new screen on update.**~~ Fixed in #256 and #259, released in client 0.18.0. It carries one known weakness worth stating rather than discovering: nothing forces a contributor to add an entry, so a release can ship user-facing changes and show none of them. That caught us on the very first one - #256 shipped the screen with entries stopping at 0.17.2, so the first build ever to carry it would have had nothing to say about itself, and #259 was the fix.
- ~~**On mobile, the context menu should slide up from the bottom rather than float.**~~ Fixed in #256, released in client 0.18.0. The desktop path keeps its positioned overlay, its keyboard scope and its focus handling untouched, exactly as this entry asked.
  One trap found on the way, worth keeping: this entry named `ContextMenuRegion` as the widget to branch, and a first pass built the sheet there - on a widget nothing renders. The message rows go through `MessageContextMenuRegion`, and `ContextMenuRegion` had no call sites at all, so its own test suite passed while covering code that never ran. It is deleted now.
- **Sending a message flashes a day divider.** "on sending a message it immediately puts a divider bar like the --today-- one and then deletes it."
  Partially diagnosed 2026-07-31, not fixed, because the obvious mechanisms did not survive checking. `isNewDay` (`message_transcript.dart:280`) returns true whenever `previous == null`, so the oldest row in the window always carries a divider - but `watchChannel` windows at 200 and only evicts at that size, so an insert does not change which row is oldest in a shorter channel. The optimistic row's ordering (`seq = 0` sorted first, then reversed to last) is also stable across the insert.
  What is left, and wants reproducing rather than guessing: whether the drift query stream emits an intermediate row set during the optimistic insert or the server-copy replacement, in which the sent message briefly has no predecessor. A speculative fix here would be a change to divider logic that is not the bug.
- ~~**Two channels overlay each other while switching.**~~ Fixed in #253: `fadeThroughPage` was a cross-fade, not a fade-through - it faded the incoming pane in while the outgoing sat at full opacity, so both were legible at once.
- ~~**One image fills the desktop.**~~ Fixed in #253: the inline preview was capped at the full message column on width and had no height bound at all, so a tall image took the screen. `kInlineImageMax` is half the column on both axes.
