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
