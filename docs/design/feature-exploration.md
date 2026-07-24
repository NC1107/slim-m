# Feature exploration: synthesis of five segment gap analyses

Status: exploration.
Date: 2026-07-23.
Input: gap analyses for five user segments (gamers, teams, power users, community organizers, accessibility).
Output: one prioritized, deduplicated view sorted into three buckets.

## How the discipline was applied

The brief is explicit that slim-m is not a feature-for-feature Discord clone and that long-term maintainability is valued over rapid feature accumulation.
Every idea below was weighed against the fixed principles: lightweight and cheap to self-host for a handful of users, one backend deployment is one community, performance is a first-class feature, and the client is Flutter for iOS, Linux, and Android.

Three filters did most of the work.
First, overlapping asks were merged so a feature is decided once, with all the segments that want it noted.
Second, a feature only earns "plan now" if the value is high and the fit is strong, with a deliberate bias toward cross-segment wins, cheap items, and anything that strengthens the lightweight, self-host, or Voice Canvas identity.
Third, a feature is declined outright when it would bloat the app, break the lightweight or one-community principles, or drag the product toward being a Discord clone, even when it is popular.

A fourth bucket exists implicitly: things the brief already covers.
The community "welcome/rules gate on join" is substantially already handled by the planned invite-time terms-of-use acceptance step, so it is treated as covered rather than as a new feature, and a per-community custom rules screen is a trivial later extension.

The strongest additions, called out in the plan-now bucket below, are operator observability plus a one-command backup CLI, a low-bandwidth data-saver mode, advanced search operators, the command palette with full keyboard navigation, client-side voice controls, and a tightly scoped webhook surface.
The single most important architectural hook to preserve is a semantic, addressable object model for the Voice Canvas, because retrofitting accessibility onto a pointer-only immediate-mode canvas is close to impossible.

## Plan now

These belong on the roadmap for v1 or soon after because value is high and fit is strong.

- **Client-side voice controls: per-user volume mixer, voice-activity sensitivity, and desktop push-to-talk** (gamers; S to M). Strongest addition.
  These are client-side mixing and input capture layered on the existing LiveKit streams with no server or infra change, and they are daily quality-of-life for the voice and canvas identity.
  Global hotkey outside app focus is best-effort per OS and falls back to in-app push-to-talk on mobile, which is honest scope rather than a blocker.
- **Screen-share audio capture plus a quality and frame-rate toggle** (gamers; M).
  LiveKit already supports both, so this is mostly client capture and a settings surface, and the quality toggle directly serves the performance-first principle by giving users explicit CPU and bandwidth control.
  Screen-share audio capture is desktop-first because Wayland audio capture is fiddly, and it lands as capture support matures.
- **Message editing with edit history** (teams; S).
  Storing prior versions on edit and showing a small history popover builds directly on the existing message model with no new subsystem, and it gives teams accountability and typo fixes.
- **Pinned messages and personal saved items** (teams, community; S).
  These are simple flags and join tables over existing messages with a small pinned-list and saved-items UI, and two segments ask for them.
- **In-chat polls** (community; S). Strong.
  A native poll message type is a small, self-contained extension that replaces the awkward reaction-counting workaround organizers improvise today.
- **Rich markdown and code blocks with lean syntax highlighting** (teams; S).
  This is client-side rendering with no server change and is table stakes for a technical audience, provided the highlighter ships a lean language subset so binary size and startup cost stay in budget.
- **Advanced search operators (from:, in:, has:, before:/after:, filename:)** (power; M). Strongest addition.
  This extends the already-planned full-text search with a query parser and a few indexed filters rather than a new subsystem, so the architectural risk is low and the power-user payoff is high once history grows.
- **Command palette and full keyboard navigation** (power, accessibility; M). Strongest addition.
  This is pure client-side UX work with no server change that directly delivers the brief's stated keyboard-navigation and accessibility ambitions, and it serves two segments at once.
- **Operator observability plus a one-command backup, restore, and export CLI** (power; M). Strongest addition.
  Prometheus metrics, structured logs, and a verifiable backup/restore path mostly wrap the metrics and database already planned, and they are core to the self-host identity and the brief's own diagnostics and health-monitoring goals.
  The data-export half of the power segment's portability ask lands here as a documented archive of an operator's own history.
- **Temporary member mute or timeout with auto-expiry** (community; S).
  This is a natural extension of the per-member RBAC overrides already in scope, needing only an expiry timestamp and a background sweep, and it gives small-scale moderators a self-expiring cooldown without permanent bans.
- **Color-blind-safe redundant cues and an adjustable UI density setting** (accessibility; S).
  Shape or icon backups for presence, roles, and mentions plus a compact/comfortable/spacious toggle are cheap design-system additions with no architectural conflict, and they pair naturally with the already-planned text-scale support.
- **Low-bandwidth and data-saver mode** (accessibility, gamers; M). Strongest addition.
  Audio-only calls and suppressed auto image loading reinforce the project's own efficient-network and lightweight principles rather than fighting them, and they serve both metered-connection users and gamers on weak links.
- **Webhooks, inbound and outbound, tightly scoped** (teams, power; M to L). Strongest addition.
  A minimal plain-HTTP webhook surface with bounded permissions and rate limits directly delivers the brief's founding Extensibility pillar without an app marketplace, and it establishes the non-human message author model that the fuller automation API will later build on.
  Slash commands are deliberately excluded from this item and appear in the decline bucket.

## Keep architecture open

Do not build these in v1, but make a data-model or protocol decision now so they are not foreclosed.
Each item names the specific hook to preserve.

- **Threaded replies** (teams).
  Reserve a nullable root or parent message reference on the message schema and keep unread aggregation groupable by a scope key, so threads can layer on later without a schema rewrite.
  They are deferred because threads shine in large busy channels and add real complexity to sync, unread counts, and search, which is weak value for the small communities slim-m targets.
- **Full bot and automation identity with an event subscription API** (power). Key hook.
  Keep the RBAC principal model capable of representing a non-human actor and keep the outbound event envelope stable and versioned, so the fuller automation API builds on the webhook principal rather than needing a painful auth retrofit.
- **Custom emoji and stickers** (power, community).
  Reserve a custom-emoji reference format in message content and reactions and plan to reuse the content-addressed dedup attachment store, so this cosmetic feature is a later addition rather than a schema change.
  It is deferred because one-community-per-backend avoids Discord's cross-server sync mess, but it remains pure feature accumulation with real picker and moderation cost.
- **Guest and restricted-visibility accounts** (teams).
  Give invites a scope field and confirm the RBAC override system can express "member who sees only channel X", which it largely already can, so a guest tier is mostly a later UI and invite change rather than a new access model.
- **Scheduled messages** (teams, community).
  Avoid baking a "created equals ordered equals now" assumption into every write path, so a deferred-send job can assign the snowflake ID at publish time later.
  The recurring and PII-bearing variant (birthdays, weekly pings) is declined below and belongs in the automation API.
- **Temporary and auto-created voice rooms** (gamers).
  Reserve channel lifecycle fields (an ephemeral flag, a creator, and a time-to-live) so ad hoc squad rooms that vanish after use are server-side lifecycle logic on the existing channel model rather than a new subsystem.
- **Live captions and transcription, plus a canvas transcript panel, as an optional module** (accessibility). Key hook.
  Reserve a per-speaker timestamped text event on the call channel that a transcript panel can render, and ship speech-to-text as an optional add-on that is never required for a lightweight self-host.
  Excluding Deaf and hard-of-hearing users from voice entirely is worse than a per-server opt-in, but forcing an STT engine into every small deployment breaks the lightweight principle.
- **Accessible Voice Canvas: a semantic object model driving a screen-reader list view and keyboard operation** (accessibility). Most important hook.
  Build the canvas as an addressable semantic scene graph of typed objects with position, size, content, author, and z-order, exposed to the accessibility tree and drivable by commands, not as a pointer-only immediate-mode draw surface.
  The full screen-reader and keyboard interaction UI can come later, but if the object model is wrong from the start, blind and motor-disabled users are permanently excluded from the signature feature.
- **Simultaneous multi-server identity** (power). Key hook.
  Keep the client data store and connection layer keyed by server and keep push registration per server and device, so signing into several self-hosted instances is a later client-only change that preserves one-backend-equals-one-community.
- **Cross-instance import and portability** (power).
  Keep the export format stable and documented and lean on the already-reserved snowflake node-id space for conflict handling, so a future importer for moving between boxes is possible without federation.
  The export half is already in the plan-now backup CLI; only the round-trip import is deferred.
- **Full localization framework with right-to-left layout** (accessibility). Key hook.
  Route every user-facing string through an i18n layer from day one and use logical start and end layout instead of left and right, so right-to-left support becomes a later flip rather than a rewrite.
  This is cheap to preserve now and brutal to retrofit, even though the ongoing translation and RTL-testing burden is why the full framework is deferred.

## Decline

Deliberately out of scope, each with a reason tied to the principles.

- **Rich presence and game status** (gamers).
  Per-OS process and game detection plus a maintained games database is a real privacy and upkeep burden that drifts straight into Discord-clone territory.
- **Soundboard for short audio clips** (gamers).
  Clip storage, playback mixing into calls, and upload moderation is non-essential ritual that sits in direct tension with the not-a-Discord-clone principle.
- **Heavy machine-learning noise suppression (RNNoise-style)** (gamers).
  A native per-platform DSP or ML dependency adds CPU cost while gaming and ongoing upkeep that cut against the lightweight and low-idle-CPU principles, so the built-in WebRTC echo cancellation and basic noise filter should simply be enabled instead of bundling a heavy denoiser.
- **Client plugin or scripting system** (power).
  A stable plugin API is a heavy long-term maintenance and security surface with no viable sideloaded-code story under App Store rules, and the webhook and future bot API are the sanctioned extensibility path that satisfies the brief without in-client dynamic code.
- **Slash-command registration framework** (teams).
  A command-registration and parsing framework is Slack-app-platform scope creep, and the command palette plus webhooks already cover the real need without it.
- **Link previews and server-side URL unfurling** (teams).
  The strategy already disables server-side unfurling by default because a lightweight self-host fetching arbitrary URLs can leak access to its internal network, so unfurling stays out unless it is ever added as an opt-in, egress-sandboxed fetcher.
- **Events with RSVP and a calendar subsystem** (community).
  A new data model, reminder notifications, and calendar UI is a real subsystem beyond chat, and polls, pinned messages, scheduled messages, and a webhook calendar integration cover the lightweight coordination need instead.
- **Scheduled or recurring channel pings that store PII such as birthdays** (community).
  A recurring scheduler plus PII storage is bot-like scope creep that belongs in the automation API rather than the core, while one-shot scheduled messages remain a preserved hook above.
- **Shared media gallery view** (community).
  A grid browser over channel media is a non-essential convenience that is declined for v1, and because it is only a filtered query over the existing content-addressed attachment store it needs no architecture hook and can be added anytime later at essentially zero design cost.
