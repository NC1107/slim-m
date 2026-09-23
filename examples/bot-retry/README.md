# bot-retry

A slim-m bot in one file, structurally identical to `bot-ping`: it answers
`!retry-test` with `pong`. The point is not the trigger, it is `send_with_retry()`
- a `send()` that actually retries an uncertain failure, which none of the
other examples in this repo do.

```bash
pip install websockets
SLIMM_URL=https://your.space SLIMM_BOT_TOKEN=slimbot_... python3 bot.py
```

## The retry contract

`docs/bots/building-bots.md` ("Sending a message") already documents this: a
send is idempotent by its client-supplied id, so a retry after a timeout is
safe, and content must never vary between attempts under one id. Every
example bot in this repo reads that section and then still only calls the
messages route once - a dropped connection or a 503 just becomes a lost
reply. `send_with_retry()` closes that gap:

1. Generate the message id once, before the first attempt.
2. Retry only on a failure whose outcome is genuinely unknown: a connection
   error, a 5xx, or a 429. Every other 4xx (400, 401, 403, 404, and 409)
   means the request itself was rejected, and an unchanged retry would just
   be rejected again - see `_should_retry()`'s own docstring.
3. Never regenerate the id on a retry. Every attempt after the first is a
   retry of the exact same logical send, and the id is what lets the server
   recognize that.
4. Back off with exponential delay plus jitter, capped at 20 seconds.

## What we proved live

This was checked against a running deployment (`testing-chat`, sample_bot)
before shipping the pattern here, not reasoned about from the source alone.

- **25 concurrent sends, one id, identical content.** All 25 requests
  returned `200` with the same `seq` and the same content. One row, no
  duplicate, regardless of how many requests raced on the write lock.
- **25 concurrent sends, one id, each with different content.** Still one
  row. Every one of the 25 responses - including the 24 that lost the race -
  came back with the single winner's content, never their own. The "never
  vary content" rule in `building-bots.md` holds under real concurrency, not
  just a single sequential retry.
- **A connection abandoned before the server had a chance to act on it**
  (the request sent, then the socket closed immediately, never reading a
  response): nothing was written. A later retry with the same id was
  correctly treated as a fresh send.
- **A connection abandoned after the server had time to fully process the
  request** (same abandon, but two seconds after sending, long enough for
  the write and an attempted response): the message existed. A later retry
  with the same id returned the original content rather than creating a
  second message or losing the first.
- **The same id reused in a different channel** (the original message and a
  thread opened from it): `409 message id already used`. Never silently
  aliased onto the wrong channel's message.
- **The same id reused by a different bot in the same channel**: `409
  message id already used`. Never silently aliased onto the wrong author.
- **A plain rate-limit `429` carries no `Retry-After` header and no
  `retry_after_seconds` field** - confirmed against the response body and
  headers directly. Only slow mode's own `429` carries one
  (`crates/slimm-server/src/http/error.rs`). `send_with_retry()` backs off on
  its own fixed schedule rather than trying to read a hint that is not sent.

All of this traces back to one design choice in
`crates/slimm-server/src/store/messages.rs::Store::send_message`: it opens
its transaction with `BEGIN IMMEDIATE` rather than a deferred one, so
concurrent attempts on the same id queue behind SQLite's write lock instead
of racing to insert two rows. The docstring on that function and on
`Store::begin_write` reasons through exactly why; this example is the live
confirmation that the reasoning holds.

## What this deliberately does not do

- **Retry a 409, or any 4xx other than 429.** A rejected request will not
  succeed by being sent again unchanged. A 409 in particular means the id
  itself was already used - by this bot for a different message, or by
  someone else - which is a bug in the caller, not a transient failure.
- **Survive the bot's own process crashing between generating an id and
  getting a response.** The id lives in memory for the duration of one
  `send_with_retry()` call. If the process is killed mid-retry and restarted,
  the bot has no memory of which id it used and would send a genuinely new
  message next time it tries. A bot whose crash recovery must never
  double-post needs to persist `(intent, id)` before the first attempt - the
  same durability argument `bot-reminders`' sqlite file makes for a
  scheduled reminder that has not fired yet.
- **Honour a `Retry-After` header on the ordinary rate-limit `429`.** There
  is none to honour; see "What we proved live" above.
- **Generalize past `sendMessage`.** The same "idempotent by a client-supplied
  id" shape appears on other routes (`openDm`, role grants, and more - see
  `schema/openapi.yaml`), and the same retry pattern applies to all of them,
  but this example only wires it up for messages.

## What we would recommend against adding

- **A `Retry-After` header on the generic rate-limit `429`.** It would be a
  small ergonomic win, but a fixed exponential backoff already behaves
  correctly against it, and 429 is rare for a bot that is not already
  misbehaving. Not worth a card on its own.
- **Any retry logic inside the server or a hypothetical bot SDK, hidden from
  the bot author.** The two failure modes proved above resolve differently
  (rolled back vs. persisted-but-unread) depending on exactly when the
  connection dropped, and a bot author who owns the retry loop can reason
  about that; a magic auto-retry could not tell those cases apart on its
  behalf and would just paper over the one case that actually matters -
  losing the id before the first attempt ever went out.
