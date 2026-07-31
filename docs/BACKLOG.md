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

- **Rows bounce on hover.** The reaction affordance renders bottom-left and reflows the row, so the whole chat log moves under the pointer. Discord's answer is a floating action cluster pinned top-right that does not participate in layout; that is the shape to copy.
- **Author icons stay vertically centred as a message grows.** They should align to the top of the text block, as Discord does. Currently a long message centres its avatar halfway down.
- **No way to highlight a message.** No selection, no jump-to, no visual mark.

### Composing

- **No markdown or list formatting in any text field.** No way to type a list at all.
- **Ctrl+V does not attach an image.** Pasting an image does nothing; it has to go through the file picker.

### The rail and DMs

- **"Notes to self" is treated as a channel under the hood and should be a DM.** It reads wrong in the list because of it.
- **The DM section is wordy**: "Notes to self" followed by "No other direct messages yet ..." as a list entry.
- **No way to reorganise, move or collapse channels in the sidebar**, and no way to collapse the left sidebar entirely to gain channel real estate.

### Voice and canvas

- **The voice lobby screen has no purpose.** Owner's standing view, repeated: the join-preview screen is not earning its place.
- **The pins button is styled differently from its neighbours** and carries a counter. It should be the same icon treatment as the rest, with no count.
- **No background blur or replacement on camera**, which Discord has and which the owner calls "kindve a required feature" rather than a nice-to-have. Worth treating as a camera-launch blocker rather than polish: people will not turn a camera on in their own home without it. Note this is a real engineering item, not a setting - it needs a segmentation model running per frame on the local track before publish, so it lands with the camera work rather than after it.

### One open product question, not a task

The owner is thinking aloud about **canvas lifetime**, and it is not decided:

> perhaps if every docker server is just one "space" we could do a file browser or something, unsure how to handle canvases, like are they forever spaces, or is it like teams where every meeting is a new meeting and chat and the canvas changes after each meeting and is just an artifact or something, or should it persist for as long as the call exists, and people clear it as they need or save/export it as they need

Three candidate models, none chosen: a canvas that is permanent per channel (what ships today), one that is per-call and becomes an artifact afterwards, or one that lives as long as the call and is cleared or exported by hand.
This is a product decision with real schema consequences - `canvas_objects` is currently keyed per channel with no notion of a session - so it belongs in [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md) rather than being resolved by whoever picks up the next canvas slice.
