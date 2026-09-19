# Building a bot

A bot is a member of your Space with a long-lived credential, not a special kind of client.
That one sentence is most of what you need: everything a bot does, it does through the same REST and WebSocket API a person's client uses, with the same permissions model deciding what it may do.

There is no bot SDK to learn and no bot-specific protocol.
If you can make an HTTP request and open a WebSocket, you can write a bot.

See `docs/decisions/0028-bot-accounts.md` for why it is built this way.

## Getting a token

Space settings -> Bots, as somebody holding MANAGE_SERVER.
Give it a username - the same rules a person's follows, so the bot is mentionable the same way - and you get a token starting `slimbot_`.

**The token is shown once.** The server keeps only a hash of it, so it cannot be shown again.
If you lose it, revoke the bot and make another.

A bot cannot create a bot, even one holding MANAGE_SERVER. Provisioning is a human act, so a single compromised credential cannot mint a second one that would survive revoking the first.

## What your bot may do

Nothing, at first.

A new bot holds exactly what `@everyone` holds in your Space and not one bit more.
To let it do something, give it a role on the roles screen, the same way you would a person.
It needs `SEND_MESSAGES` to talk, `VIEW_CHANNEL` to read a channel, `MANAGE_MESSAGES` to delete somebody else's message, and so on.

Per-channel overwrites apply too, so a bot can be allowed in one channel and not another without touching its roles.

A bot is exempt from nothing. Not slow mode, not message retention, not moderation.

## Authenticating

Exactly like any client:

```
Authorization: Bearer slimbot_...
```

Call `GET /me` first. It returns the bot's own id and its effective base permissions, which is the cheapest way to confirm the token works and to learn the id you will need to avoid answering yourself.

## Receiving events

Events come over the WebSocket, and getting on it is two steps:

1. `POST /auth/ws-ticket` with your token. It returns a single-use `ticket`.
2. Open `/ws`, then send a hello frame:

```json
{ "type": "hello", "ticket": "...", "protocol": 1 }
```

The server replies with its own `{"type":"hello","protocol":1}`, and after that the connection carries events.

You only receive what your permissions allow - fan-out is authorized per connection, so a channel your bot cannot view never reaches it.

A frame you do not recognise should be ignored, not treated as an error.
New event types are added over time, and a bot that dies on one it has never heard of breaks on somebody else's upgrade.

## Sending a message

```
POST /channels/{channelId}/messages
{ "id": "<a uuid you generate>", "content": "pong" }
```

The `id` is yours, and it makes the send idempotent within the channel: retrying with the same id returns the message already stored rather than sending twice.
So a retry after a timeout is safe.
Never vary the content between attempts under one id - the server replays what it first stored, whatever the retry carried.

## Answering yourself

A bot that posts in a channel it also listens to will see its own message arrive as an event.
Check the author against your own id from `GET /me` before answering, or the bot will talk to itself forever.

This is the single most common way a first bot goes wrong.

## When a token is revoked

Revoking closes the bot's WebSocket and makes the next REST call return 401.
It takes effect immediately, not at some expiry.

A 401 is therefore not something to retry: back off on a network error, but treat a 401 as "stop, the credential is gone".
The account itself stays, so everything the bot wrote stays attributed to it.

## The example

[`examples/bot-ping/`](../../examples/bot-ping/) is a working bot in one file: it answers `!ping` with `pong`.

```bash
pip install websockets
SLIMM_URL=https://your.space SLIMM_BOT_TOKEN=slimbot_... python3 examples/bot-ping/bot.py
```

It does the five things above and nothing else, so it is short enough to read in one sitting.

It refuses to connect over plain `ws://` to anything but a loopback address.
A bot token is long-lived, so putting one on the wire in the clear is the one leak a bot cannot recover from - `http://localhost` is a developer's own machine, and anywhere else needs https.
What it deliberately leaves out, and what a bot doing real work needs:

- **A cursor.** It only sees what arrives while connected. A bot that must not miss anything records the `seq` on each event and calls `/sync` on reconnect to catch up.
- **Backoff.** It reconnects on a flat delay. Use exponential backoff against a real deployment.
- **Scoping.** It answers in any channel it can see. Most bots should be told which channels are theirs.

## Where a bot should live

Your own repository, deployed however you like.
A bot is an ordinary program that holds a credential; it does not go in the Space, and slim-m never runs it.

That is the difference between a bot and a **module**.
A module is sandboxed wasm that slim-m runs for you, with no network and no identity of its own - see [`docs/modules/building-modules.md`](../modules/building-modules.md).
Reach for a module when you want to extend the app's own surfaces (a command, a code-block runner, a drawing).
Reach for a bot when you want a program that acts on its own, on its own schedule, from somewhere else.
