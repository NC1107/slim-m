# 0034 - When something is a module and when it is a bot

Status: accepted
Date: 2026-09-28

## The ask

The owner, 2026-09-25: "better determination on whether something should be a module or a bot".

Both are generalised primitives, and they are drifting into each other's territory.
A bot wants in-call controls, which is a surface.
A module wants to post messages and remember things, which is an identity and state.
Nothing told a contributor which one to reach for, so the answer was being decided card by card.

This record gives a test that takes about a minute, says which side wins when both apply, and sorts the work already on the board.

## What each one is

A bot is a user-shaped principal that a program someone else deploys authenticates as ([0028](0028-bot-accounts.md)).
It holds a long-lived credential, has roles, is moderated, and lives outside the server process.

A module is sandboxed WebAssembly the host runs ([0021](0021-modules-and-the-dock.md)).
It gets an input and returns an output, has no ambient authority, and reaches the host only through named capabilities an admin approved ([0023](0023-mediated-host-capabilities.md)).

The short version: a bot is somebody, and a module is something the client draws.

## The decision

**Use the checklist below, in order, and stop at the first hit.**
The first two questions decide most cases, because they are about what the sandbox cannot do.

1. Does it need a long-lived secret, or to reach a third-party or LAN service (Jellyfin, a game server, a panel API)? It is a bot. A module has no network and holds no secrets by design.
2. Does it need to run on its own schedule, or react to events with nobody present? It is a bot. A module runs only when a member acts, per viewer.
3. Does it need an identity people can see, mention, moderate, or grant permissions to (it posts as itself, joins a call, is blocked or removed)? It is a bot.
4. Is it an interactive surface rendered inside a message, a scene or the Dock, that is pure, sandboxed, and safe to run from any member's click? It is a module.
5. Is it neither, because it is a property of the client or the server itself? It is core, and a card for the client or server, not a new primitive.

**When both apply, split it: the bot owns state and outside access, the module owns the pixels.**
The bot is the authority (it holds the secret, talks to the outside service, and posts or edits the message).
The module renders what the message carries and sends the viewer's input back as an ordinary action the bot receives over the same API a person uses.
The module never gets the secret and never needs a network.
If the only thing the module would need is to post or remember something on the viewer's behalf, that is a mediated capability under 0023, not a reason to make it a bot.

**Where they overlap, the bot wins on trust and the module wins on rendering.**
Anything that needs a credential or the network is never a module, however small.
Anything that only draws is never a bot, however interactive.

**Decision, 2026-09-28: no personal access tokens.**
Automation goes through bot accounts, which are scoped, audited and revocable.
A person's own credential is never handed to a script.
This closes the personal access token question: a contributor who wants to automate something makes a bot, and the checklist above decides whether a module is also involved.

## The worked cases

| Case | Answer | Why |
| --- | --- | --- |
| Jellyfin watch party | Both | Bot: holds the Jellyfin credential, is the sync authority, posts the invite. Module: the native video surface. They talk through the message and the bot's API actions. |
| Pelican panel | Bot | Needs the panel API key and a LAN or third-party network call (checklist 1). Any status card it posts is plain message content. |
| Minecraft bridge | Bot | Long-lived connection to a game server, runs continuously with nobody present (1, 2), relays as its own identity (3). |
| Starboard | Bot | Reacts to reaction events over time and posts as itself (2, 3). |
| Automod | Bot | Reacts to every message, holds MANAGE_MESSAGES, must be auditable and revocable (2, 3). |
| Music bot | Bot | Joins the voice call as a participant and streams audio (3). A player card is optional and would be a module. |
| Mini-games pack | Module | A board rendered in a message, pure, per viewer, safe from any click (4). Already how connect-four and the others ship. |
| Homelab dashboard | Both | Bot: polls the LAN services and holds the credentials (1, 2). Module: renders the panels in the Dock from what the bot posted. |
| Rich presence | Neither | "Listening to" is core presence, a client and server field. It follows checklist 5, not a new primitive. |
| Code runner | Neither, a brokered service | The server brokers a submission to an operator-run Piston instance and never executes it ([0026](0026-polyglot-code-runner.md)). The odd languages stay modules. |

## What this changes

- `docs/modules/building-modules.md` and `docs/bots/building-bots.md` each link here in one line.
- A module card that needs a secret or the network is re-scoped as a bot, or split as above.
- A bot card that only renders a surface is re-scoped as a module.
- Rows that sit wrong today are named as follow-ups on the board rather than fixed here. This record is docs only.

## What this does not decide

- Which capabilities a module may eventually hold. That stays with 0023, one review each.
- The wire between a bot and a module for a split case. The first one built (the watch party) settles it, and it gets its own record then.
