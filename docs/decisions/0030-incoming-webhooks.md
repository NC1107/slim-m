# 0030 - Incoming webhooks, and the authorship model they force

Status: proposed (design; nothing here is built, and the open questions at the end are the owner's)
Date: 2026-09-23

## The gap

slim-m has no incoming webhooks.
`webhook` appears zero times in `crates/slimm-server/src/` and zero times in `schema/openapi.yaml`.
The only traces anywhere are aspirational: `docs/PRODUCT.md` names webhooks as "the sanctioned extension point instead of a plugin system", `docs/design/feature-exploration.md` calls a tightly scoped webhook surface one of the strongest additions, and `client/packages/app/lib/src/widgets/message_row.dart` carries a `isWebhook` flag with a `TODO(ui-backend)` saying in as many words that there is no webhook feature in the product at all, wired to an `AppBadge` labelled `Webhook` that no real call site can ever set true.

The design has been promised for a year and the badge has been sitting there waiting for it.

This is the largest remaining gap between slim-m and the ecosystem it wants to live in, and the reason is narrower than "we lack integrations".
The self-hosted world does not speak "bot".
It speaks "paste a webhook URL".

Sonarr, Radarr and Jellyfin ship Discord webhook targets in the box.
Uptime Kuma carries dozens of notification providers with Discord and Slack among the first.
Gitea, Grafana, Home Assistant, Immich and Paperless all do the same, and Apprise bridges the long tail of everything else.
In every one of those, adding slim-m today means somebody writes and hosts a program.
Adding slim-m with this record means somebody pastes a URL into a field that already exists.

Decision 0028 does not cover this, and a bot is not a substitute for it.
A bot is a program someone deploys, holding a credential, that polls or listens.
A webhook is a URL pasted into a plugin that was written before slim-m existed.
The two solve different halves: 0028 gives an author of automation somewhere to authenticate; this gives somebody who will never write a line of code an integration.

## The question this record exists to settle

Two, really, and they are entangled.

Do we accept Discord's payload shape, with the costs that carries?
And if a webhook posts a message, what is that message's author, in the model?

Everything else here is consequence.

## Decision 1: accept Discord's incoming-webhook payload, and promise to accept rather than to honour

**The delivery route accepts a Discord incoming-webhook body.**

Mattermost and Rocket.Chat both ship Slack-compatible incoming webhooks for exactly this reason, and Discord itself accepts a Slack body when you append `/slack` to a webhook URL.
Nobody in this space invents their own shape, because the shape is not the product - the compatibility is.
Accepting `{content, embeds, username, avatar_url}` means every tool listed above works against slim-m with zero slim-m-specific code, no plugin written, and no upstream project asked for anything.

Concretely, the route is `POST /webhooks/{webhook_id}/{token}`, and it is the only route in the product that authenticates with a webhook credential.
A tool takes a whole URL, so the path prefix is ours to choose and the body is not.

What makes this affordable is bounding the promise.
The promise is **acceptance, not fidelity**, and the two halves are stated separately:

- **An unknown field is ignored and the request still succeeds.**
  This is the whole compatibility contract.
  A Sonarr release that starts sending a field we have never heard of must not turn a working notification into a 400 on somebody's self-hosted box, because the person who upgraded Sonarr has no idea slim-m is the thing that broke.
  Silently ignoring an unknown field is the opposite of this repo's usual rule - `attachment_ids` deliberately 400s on an id it does not recognise rather than dropping it - and the inversion is deliberate: there, the caller is our own client and a silent drop hides our bug; here, the caller is somebody else's program and a loud refusal hides theirs.
- **The honoured subset is documented, small, and ours.**
  `content`, `embeds`, `username`, `allowed_mentions`.
  Everything else in Discord's body - `tts`, `flags`, `components`, `thread_name`, `poll`, `attachments`, `avatar_url` - is accepted and discarded, and `schema/openapi.yaml` says so field by field.

Our own limits must never be the ones that bite, so the per-field ceilings mirror Discord's documented ones rather than being invented here.
The existing `content` cap helps: `SendMessageRequest.content` is 4000 characters against Discord's 2000, so no compatible caller can overflow it.

**Rejected: a slim-m-native payload only.**
It is the shape nobody will ever implement.
The entire value of this feature is that the integration already exists upstream, and a native-only body throws that away to save writing a translation layer once.

**Rejected: Slack-compatible as the primary shape.**
Mattermost and Rocket.Chat chose Slack because they were competing with Slack.
The tools slim-m needs ship Discord targets as first-class and Slack targets as the other option, and Discord's own `/slack` suffix shows the compatibility layer is the cheap additive half.
Discord-shaped now; a `/slack` suffix later if a tool the owner actually runs ships only a Slack target.

## Decision 2: a webhook message has a real author, and that author is the webhook

This is the hard part, and it is the reason this record exists.

**A webhook is a user-shaped principal, one `users` row per webhook, and its messages carry that row's id in `author_id`.**

This is decision 0028's argument applied a second time, and 0028's argument is the house position: a bot is a row in `users` with a flag, because slim-m already has one answer to every question a non-human author raises and that answer is "the same as for a person".
The same holds here, and the payoff is concrete rather than tidy:

- Who wrote this? A `users.id`, which every read path already joins and every client already renders.
- Can it be reported? Yes, with no change to `http/safety.rs`: `file_report` takes `subject_kind: "message"` and only requires that the reporter can see the message, and the stored report snapshot names an `author_id` that an operator can look up.
- Can a moderator delete it? Yes, by `MANAGE_MESSAGES`, with no hierarchy to consider (0016).
- Can a member block it? Yes, because blocking is keyed on a user id and a webhook has one.
- What happens to its messages when the webhook is deleted? The same as anyone's, because account deletion is a tombstone `UPDATE` and the messages stay attributed.

**Rejected: a nullable `author_id` with a display label beside it.**
`author_id IS NULL` already has a meaning, and `schema/openapi.yaml` states it: "Null once the author's account has been deleted", with `author_display_name` going null in the same breath and clients rendering their own fallback off exactly that.
Giving one null two meanings would put the distinction into every read path and every client that renders an author, and none of them currently need to ask.
Worse, a null author is not a principal, so there would be nothing to authorize the write against - a second answer to a question already answered, which is where authorization bugs live.

**Rejected: reusing `users.is_bot`.**
A new `users.is_webhook` flag, mirroring how 0072 added `is_bot`, because the two differ in what they may do rather than only in how they are labelled.
Sharing one flag would mean the member list, the badge, and the ws-ticket path all had to re-derive which kind they were looking at.

### Where this departs from 0028, deliberately

**A webhook has a principal but no session.**

0028's key move was that a bot token resolves to a real `sessions` row, which is what lets a bot mint a ws ticket, be revoked by `revoke_session`, and be authorized per subscriber with no second code path.
A webhook must not have that, because a session is what makes a credential able to *read*, and a webhook must never read.
Its credential resolves to a webhook row carrying a principal id and a channel id, and nothing else.

**A webhook is not a member and holds no roles.**

0028 gave a bot roles because a bot has the whole API surface in front of it and needs the permission system to decide what it may touch.
A webhook has exactly one verb on exactly one channel.
There is nothing to resolve, so the authorization check is "is this webhook live, and is its channel live", and that is not a second authorization path - it is the absence of one.

Giving a webhook a membership row instead would be worse in two specific ways.
Per-channel overwrites (0011) written for people would start deciding webhook behaviour, so a role grant could hand a webhook `MANAGE_MESSAGES` or `MENTION_EVERYONE` bits it has no route to use but that a reviewer would then have to reason about.
And a member row counts: `roles.rs::administrator_count` is the last-administrator guard, and 0015 records that missing one such read let a Space be walked down to zero reachable administrators once already.
A principal that is not a member cannot be miscounted by a query nobody remembered to change.

This means a webhook is **not in the member list**.
It is not a participant, and a member list padded with fifteen alert feeds is noise.
Webhooks are listed in their own admin surface, where the thing an operator wants - which channel, who minted it, when it last delivered - actually lives.

### `username` becomes a label; `avatar_url` is dropped

Discord's `username` and `avatar_url` are identity spoofing by design, and that is not an accusation - it is the feature. A webhook posts as any name with any picture.
slim-m's authorship model is the opposite: a real `author_id` that survives deletion, and an `author_display_name` that goes null with it.

The split taken here is that **a name is text that a badge can sit next to, and an avatar is an identity claim with a network fetch attached.**

`username` is honoured, as a per-post label stored on the webhook message's side row.
It is never written to `users.display_name` and never returned as `author_display_name`.
It is not mentionable, not resolvable to a user, and never checked for collision with a real member's name - because refusing a collision would mean a working integration breaking on the day somebody joins with an unlucky display name.
Instead the collision is made visible rather than prevented: the row renders the label in the name slot with the `Webhook` badge immediately adjacent, which is the badge `message_row_identity.dart` already draws and which nothing has ever been able to set.
The badge is the whole mitigation, and it is why it has to be adjacent and unconditional rather than a hover affordance.

Honouring the label at all is a real concession, and it is there for one concrete case: Apprise and Uptime Kuma users point several sources at one webhook and rely on `username` to tell a disk alert from a certificate alert.
Refusing it would make one webhook per source the only usable pattern.

`avatar_url` is **dropped**.
An avatar is the strongest impersonation signal at a glance, and unlike a name there is no text beside it for a badge to qualify.
Honouring it also means either the server fetches an arbitrary caller-supplied URL per post, which is 0019's SSRF surface reopened for a cosmetic field, or the client fetches it and every viewer's IP goes to whatever host the caller named.
Neither is worth a picture.
The avatar slot instead shows the webhook's own configured avatar, and `message_row_identity.dart` already has a fallback for a webhook row: a bordered box with the code glyph.

**Rejected: honouring `avatar_url` through the link-preview proxy.**
It would work, reusing 0019's guard and proxy rather than writing a second fetcher, and it is the natural-looking answer.
It is rejected because it spends a per-post outbound fetch and a proxy-storage row on the one field whose only function is making a machine look like a person.

### Where `embeds` live

`Message` in `schema/openapi.yaml` has `content`, `attachments`, `reactions`, `poll`, `app_surface`, `code_runs`, `call`, `forwarded` and the thread fields.
It has no embed, and every one of those was a decision.

**Embeds go in a side table, `message_embeds`, enriched onto the DTO on read.**

This is the rule this repo already follows and already wrote down: per-message data belongs beside the message, not as a field on the row that ten `SELECT`s carry.
0019 reached the same conclusion for link previews ("follow the attachment precedent, not a column on `Message`"), and `http/message_enrich.rs` is the shared batch-enrichment path that exists precisely so list, search, sync and the pinned list all attach side data the same way - it exists because doing it per route once shipped `/sync` deltas with an empty `reactions` array.
An embed attaches there, in the same batched query shape, or it will be the next thing that is present on one read path and missing on another.

**Rejected: flattening embeds into markdown.**
Two reasons, and the second is the disqualifying one.
The flattening rules become a surface we maintain forever, in a translation layer that has no specification and no test oracle beyond "does this Grafana alert look right".
And a flattened embed is indistinguishable from text the caller wrote, which throws away the only structural handle a client has for rendering a machine's output differently from a person's - immediately after this record spent a section arguing that a webhook's output must be visibly not a person's.

**Rejected: `Message` grows an `embeds` field.**
It is the same trade the repo has already refused twice, and the memory of why is short: a field on `Message` is a field every read path must carry, forever, for the small fraction of messages that have one.

Embed images are caller-supplied URLs and get 0019's treatment exactly, with no new fetcher: the same `is_blocked` guard over every dialed address, the same manual redirect handling, the same size and content-type caps, and the same server-side proxy so a viewer's IP never reaches the third-party host.
An image the guard refuses is **dropped, and the rest of the embed still posts.**
This matters more than it sounds: a Grafana panel snapshot commonly sits on an internal host, so the guard refusing it is the expected case, and failing the whole delivery over it would mean the alert text never arrives either.

## Threat model

A webhook URL is a bearer credential, in plaintext, that posts into a channel, held in somebody else's configuration file.
Assume it leaks.

### Leak

The blast radius is the design, not a mitigation bolted on after.
A leaked webhook URL can post text and bounded embeds into exactly one channel, at a rate limit, visibly badged as a webhook, and nothing else.
It cannot read a single message.
It cannot edit or delete anything, including its own posts.
It cannot upload a file.
It cannot mention `@everyone`, `@here`, or a role.
It cannot mint another webhook or a bot.
It cannot reach any other route in the product.
It dies the moment somebody clicks revoke.

That list is the answer to "what happens when this leaks", and it is short on purpose.
Compare a leaked bot token, which reads history.

Two leak paths are ours to close rather than the operator's:

**The token is in the URL path, so anything that logs paths logs the credential.**
`http.rs` mounts `TraceLayer::new_for_http()`, whose default span records the request URI.
On a deployment running at debug level, every webhook delivery would write its own token into the log.
`route_timing.rs` is already safe here and says why in its own doc - it labels by `MatchedPath`, the route template, never the raw path, because a caller controls parts of the path on many routes - but the trace span is a separate thing and would need an explicit redacting `make_span_with`.
Putting the token in a header instead would fix this and is not available: a tool that takes one URL field cannot send a header, and paste-ability is the entire feature.

**The shipped `deploy/Caddyfile` has no `log` directive, so Caddy is not writing access logs today.**
An operator who turns them on will start logging webhook tokens, and `deploy/README.md` should say so beside the instructions that enable it.

### Replay

A captured delivery can be replayed to repost the message.
This is **accepted, and it is not a separate threat**: anyone able to replay a captured request already holds the URL, and the URL lets them post whatever they like.
Replay adds nothing to a leak, so defending it separately buys nothing.

What is worth handling is the honest case that looks identical: a tool whose request timed out and retried.
The native send path keys idempotency on a client-generated UUIDv7, and a Discord payload has no id field, so there is nothing to key on by default.

**No automatic body-hash deduplication.**
It is tempting and it is wrong here: a heartbeat webhook legitimately posts a byte-identical body on a schedule, and silently dropping a message is the failure this repo consistently refuses.
Instead, an `Idempotency-Key` request header is honoured when a caller sends one, resolving to the same stored-message-returned behaviour the native path already has.
A caller that sends nothing gets at-least-once delivery and a duplicate alert on a retry, which is noise, not a defect.

### Abuse

**One POST wakes every phone in the community.**
That is the amplification factor that actually matters, and it is why the rate limit cannot be reasoned about as a write.
A webhook message fans out over the hub and fires push notifications through the relay, so a loop against a webhook URL is closer in cost to `Class::Ring` - whose doc records exactly this reasoning, that one request "fires an outbound push through the relay, wakes a device, starts a looping tone" and therefore cannot ride `Write`'s budget.

So: **a new `Class::Webhook`, sized against push cost.**
Sustained refill well under one per second; burst generous enough for the honest bursts an alert feed produces, which are real - a flapping monitor, or an import that lands thirty episodes at once.
Following 0028, the concrete numbers are sized when the surface is built, against that workload, not guessed here.

Per-member control over the noise needs nothing new: `channel_notification_prefs` already lets somebody mute a channel, and an alert channel is exactly what people mute.

**Two buckets, and the order matters.**
The per-webhook bucket keys on the webhook's own principal id, never on the caller's address - 0028's reasoning, that a bot is a server and its address says nothing about who is calling, applies identically to a CI runner with rotating egress addresses.
`limit_key` in `http/extract.rs` already produces `u:{user_id}` for an authenticated caller and falls back to the peer address only when there is none, so keying correctly here means making sure the delivery route resolves its principal *before* charging, and never takes the IP branch.
But that resolution costs a database lookup, so there must also be an address-keyed bucket charged *before* the token lookup, or an unknown-token flood costs a query per request instead of a map probe.
Brute force is not the threat the second bucket answers: the token is 32 bytes from `generate_secret`, so guessing it is not happening.
Flooding is.

**A uniform 404.**
No such webhook, wrong token, revoked, and channel deleted all answer identically, so the endpoint is not an oracle for which webhook ids exist.
The operator's signal comes from the admin surface, which shows last delivery, not from the response body - the same shape `bot_tokens.last_used_at` already has.

**No new SSRF fetcher.**
Embed images go through `http/link_preview`'s existing guard, unchanged.
A second copy of that guard is how one of them ends up missing a bypass class.

## The rest of the surface, decided

**Who may mint one: `MANAGE_SERVER`, deployment-wide, exactly as a bot.**
A webhook URL is a bearer credential that posts into the community, and the person who may create one should be the person who may create a bot.
Discord makes this a channel-level `MANAGE_WEBHOOKS` bit, which spreads credential minting to anyone who can manage a channel.
There is no such bit here, the permission set is a deliberate eighteen, and adding a nineteenth to delegate credential minting is a bigger decision than this feature needs to make.
Per-channel delegation stays available as a purely additive follow-up if the owner wants it.

**One-time reveal, and rotatable.**
The URL is shown once at creation and hashed at rest with the same `hash_secret` every other credential uses - the shape `bots.rs` documents as "a credential a server can re-read is a credential a stolen database hands over", and the shape the admin reset codes already use.
Discord lets you re-read a webhook URL from channel settings.
We do not, and the recovery path is rotation: minting a new token on the same webhook, killing the old one in the same transaction, keeping the same principal so everything it has already posted stays attributed to it.
The cost is honest - "copy it again" becomes "rotate and re-paste", which breaks anything else that was using the same URL - and it is the right trade, because a webhook is one channel and should be one tool, and sharing one URL across tools is a pattern worth making inconvenient.

**Scoped to one channel, fixed at mint, never editable.**
Re-pointing a URL that is already pasted into somebody else's configuration is silently redirecting their traffic.
If the target should change, mint another one.

**Channel deleted means webhook dead**, by `ON DELETE CASCADE` on the channel reference, answering the same uniform 404.
Messages it already posted follow the channel, like everything else in it.

**Revocation is immediate and total**, and simpler than a bot's.
There is no session to revoke and no socket to kill, so the row going away is the whole of it - no `SessionRevoked` fan-out, no already-open connection that outlives the response to its own leak.

**Mint, rotate and revoke go on the moderation audit trail** (0015), with the acting human as `actor_id` and the webhook's own principal as `subject_id`, which works because a webhook is a `users` row and `moderation_audit_log.subject_id` is `NOT NULL REFERENCES users(id)`.
One trap, stated so it is not discovered late: `moderation_audit_log` constrains `action` with a `CHECK`, SQLite cannot widen a `CHECK` in place, and 0049 had to rebuild the table to add one action.
Adding webhook actions is that same rebuild, and 0049's own header records the `foreign_keys=ON` cascade trap that cost 0034 its first attempt.

## What a webhook must never be able to do

0028 has `require_human` in `http/bots.rs`: a bot holding `MANAGE_SERVER` still cannot mint a bot, so a single compromise cannot fork itself into a credential that survives revoking the first.
The equivalent here is structural rather than a function call, and that is stronger.

**A webhook credential authenticates exactly one route.**
It never produces a `SessionContext`, so no `Authed` extractor can ever accept it, so there is no "webhook holding `MANAGE_SERVER`" to defend against.
This should be asserted rather than assumed: a test in the shape of `tests/rate_limit_coverage.rs`, which already asserts that no `Authed` handler charges the unauthenticated `Read` class, over the claim that the delivery route is the only place a webhook token resolves.

Beyond that, and part of the contract rather than the implementation:

- **A webhook cannot read.** No history, no member list, no ws ticket, no `/version` behind auth. This is the single biggest difference from a bot and the main reason a leaked webhook URL is far less bad than a leaked bot token.
- **A webhook cannot edit or delete, including its own messages.** This is a real, deliberate loss of Discord parity - Grafana-style "alert resolved" updates edit in place - and it is listed as an owner question below rather than quietly taken.
- **A webhook cannot mention broadly.** `@everyone`, `@here` and role mentions never resolve from a webhook message, because it holds no `MENTION_EVERYONE` bit and no roles and there is no code path that could grant it either. Individual `@name` mentions do resolve, because paging the on-call person is the point of an alert. `allowed_mentions` is honoured **as a restriction only**: it may narrow what resolves and can never widen it, so a careful tool sending `parse: []` gets exactly what it asked for and a careless one cannot ask for more than it already has.
- **A webhook cannot upload files.** No multipart, despite Discord supporting it. Files would give the storage ceiling and the orphaned-attachment sweep an unauthenticated writer, and embed image URLs already cover the case tools actually use.
- **A webhook is not exempt from anything.** Slow mode applies, since it is keyed per author and a webhook is an author, and it is exactly the "this channel should not be flooded" control. Retention applies, so alerts age out like any message. If slow mode turns out to be wrong for an alert channel the answer is a per-webhook budget, not an exemption in the send path - 0028's rule that where a bot needs a different budget "that is a rate-limit class, not an exemption".

## Response shape

204 with no body by default.
`?wait=true` is honoured, because some tools set it, and answers with a minimal `{id, channel_id, seq, created_at}` rather than the full `Message` DTO.
The full DTO carries per-viewer fields - `mentions_me`, and `reacted` inside each reaction summary - which have no meaning for a caller that is not a viewer, and enrichment an unauthenticated caller has no business being handed.

## Staging

Each stage stands alone, and nothing before the last is visible to an integration author.

1. **The principal.** `users.is_webhook`, the `webhooks` table, and the client reading the flag into the `isWebhook` that `message_row.dart` has been carrying unused. No delivery route yet, so nothing can post.
2. **Delivery.** The route, the Discord-shaped body for `content` and `username` only, the two rate-limit buckets and `Class::Webhook`, the uniform 404, the trace-span redaction, and the `schema/openapi.yaml` entry the contract gate requires.
3. **Embeds.** `message_embeds`, the enrichment in `message_enrich.rs`, the bounded field caps, the image proxy through `link_preview`'s guard, and the client card.
4. **Admin UI and audit.** Mint, list, rotate, revoke, with the one-time reveal and the last-delivery column, plus the `moderation_audit_log` rebuild for the new actions.
5. **Operator documentation.** A `docs/webhooks/` page in the shape of `docs/bots/building-bots.md`, saying which field of Sonarr, Uptime Kuma and Grafana to paste the URL into, what we honour, and what we ignore.

Two practical notes for whoever picks up stage 2.
`GET /version`'s `capabilities` array is derived by probing the real router rather than from a hand-kept list, precisely so a claim cannot rest on somebody remembering to update it (0007), so advertising `webhooks` there is how a client decides whether to show the admin surface.
And the delivery route is unauthenticated machinery with no client binding by design, so the `schema_coverage` and `app_reachability` gates that normally require a new route to have one will need an explicit exemption rather than a fake caller.

## What this record does not decide

**Outbound webhooks.**
`docs/design/feature-exploration.md` names inbound and outbound together, and they are not one feature.
Outbound is our server POSTing to a URL somebody supplied, which is 0019's SSRF problem with a delivery queue and a retry policy attached.
It belongs in its own record.

**Whether this should instead sit behind 0007's extension broker.**
0007 says the broker "covers webhook and bot authorship", and that line should not be read as blocking this.
A broker exists to sandbox something that executes; a webhook executes nothing, it is an HTTP POST that writes a row.
If the broker is ever built, a webhook is not the thing that needed it.

**A `/slack` compatibility suffix.**
Cheap and additive once the Discord path exists; not worth building before a tool demands it.

## Open questions for the owner

- Confirm accepting Discord's payload shape at all, versus a slim-m-native body that would need a plugin written per tool.
- Confirm dropping `avatar_url`. The compatibility cost is cosmetic and the alternative is a proxied per-post image fetch for the sole purpose of making a machine look like a person.
- Confirm no edit-in-place, which is the one genuine Discord-parity loss here and which "alert resolved" style updates rely on. What would settle it is a tool in the owner's own stack that only speaks edit, rather than posting a second message.
- Whether `username` should be honoured as a label at all, or refused outright so a webhook always posts under the name it was minted with. Refusing is stricter and costs the one-webhook-per-source pattern; what would settle it is whether the owner expects to point Apprise or Uptime Kuma at a single URL.
- Whether per-channel delegation (a nineteenth permission bit) is wanted, or `MANAGE_SERVER` is the right bar on a one-community deployment.
