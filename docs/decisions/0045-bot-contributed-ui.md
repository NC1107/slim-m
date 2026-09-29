# 0045 - Menu entries and call controls a bot contributes

Status: accepted, implemented
Date: 2026-09-29

## The ask

The owner, 2026-09-25: "can we perhaps expose some sort of additional functionality to allow a bot to add some sort of UI elements to hit apis and do extra stuff in a call, or have specialized context options or something?"
It came up while looking for a better way to drive Jellyfin playback than typing `!pause`.

This record stacks on 0031 (registration), 0037 (private replies) and 0039 (buttons and the interaction).
0039 built the primitive all three surfaces need: a typed event to the owning bot carrying who acted, an answer window, and a private reply anchored on the interaction.
This record adds two more places a member can start one, and does not add a second kind of interaction.

## What it is

- A bot registers, in one bulk overwrite, `message_menu` entries (rows in a message's context menu) and `call_controls` (buttons in a call's dock).
  Each is an id, a label, and optionally a `permission` bit.
  A call control may also name an `icon` from a fixed list.
- `GET /channels/{c}/bot-ui` lists, per bot, what the caller may be offered in that channel.
- `POST /channels/{c}/bot-ui/{botId}/interactions` uses one.
  The bot receives the same `interaction.created` frame as a button press, with `kind` set to `message_menu` or `call_control`, the entry id as `custom_id`, and the member's id and display name.
  A menu entry also carries the message it was used on; a call control carries none.
- The answer is the same as for a button: `sendEphemeralMessage` with `interaction_id` (three replies at most), or `acknowledgeInteraction`.
  The member's control shows pending until then and fails visibly after about five seconds.

## Decisions

### Registration reuses the 0031 shape, in its own route and table

`PUT /bots/ui` is a bulk overwrite in one transaction, like `PUT /bots/commands`, so a bot re-sends its whole set on connect and a dropped entry disappears.
It is a separate route rather than more fields on `setBotCommands` because that call replaces a bot's whole command registration: a library that does not know about this surface would erase it on its next connect, or the reverse.
`crate::bot_ui::validate` is the only writer of the caps, and the same shape serves the wire and storage.

### The interaction row gains a kind, not a sibling

`interactions` gets a `kind` and a nullable `message_id`, by rebuilding the table in place in migration 0088.
It is a quarter-hour table, so the copy is trivial, and the alternative was a second table with its own sweep, answer marker and anchor resolver.
Every path that already works on a press (the ack route, the private-reply anchor, the budget, the sweep) works on a menu use or a call control unchanged, because none of them read anything but the bot, the presser, the channel and the window.
The one place that read `message_id` (replacing a message's buttons while naming a press) now compares against `Some(message_id)`, so a menu use cannot be smuggled in as the press of a different message.

### Caps

At most 5 menu entries and 8 call controls per bot.
A label is 32 characters and an id 64 of letters, digits and `-_.`, unique within its surface.
The label goes through `http::hidden_chars`, the same test as display names and button labels, so it cannot reorder or hide its own text.
The client additionally shows at most 10 bot rows in one menu, however many bots register, so several chatty bots cannot bury the app's own entries.

### Who sees an entry

Only members who can view the channel, and only entries of bots that are present there: a live token, still in the Space, and holding `VIEW_CHANNEL` in that channel, the same checks as the command list.
An entry that names a `permission` is left out for a caller who lacks that bit.
Unlike a command's permission, which is a composer hint because the server never sees the message it becomes (0031), this one is also enforced on use, because the server is the one delivering the interaction.
The route answers a bot that has left, an unregistered entry, an entry the caller may not use and a message outside the channel with the same 404.
The caller cannot be a bot, so bots cannot drive each other.
It is charged to the button-press rate limit class.

### A bot cannot pass for the app

Bot rows never sit among the app's own.
They come after everything the app offers, each bot's rows under a header with the bot's name and a Bot badge, and every row leads with the same bot glyph.
A bot chooses text and an id, never an icon for a menu row and never a colour or a tone, so it cannot borrow the danger style of Delete or a built-in's glyph.
Call controls sit in their own row of the dock, above the call's own controls, under the same name and badge.
A call control's icon comes from a fixed list drawn from the app's own icon set.

### Call controls: what a bot may render, who sees it, and when the bot goes away

A bot may render up to 8 labelled buttons, each with one of ten glyphs, and nothing else: no text field, no progress or position display and no layout choice.
Position, and any state that changes as it plays, stay out for now (see below).
They appear in the call's dock only while the bot is a participant of that call, read off the roster the client already holds, so a bot that leaves takes its controls with it and nothing is left pointing at a process that is not there.
Everyone on the call sees them, since anyone on the call can use them.
A member who is not on the call gets a 403 on use: viewing a voice channel is not being in its call, and the server already knows who is on a call from the call heartbeat.
A control's use is best effort like a press: silence shows an error on the control with a retry, and a bot that is offline simply never answers.

### Delivery is best effort

Same as 0039.
The use and its answer ride the ephemeral class, with no catch-up path.

## Client

Message menu: `MessageActions.botSections` are appended by `MessageContextMenuRegion` after the app's rows.
Layout follows width: this is the existing context menu, a floating menu with a pointer and a bottom sheet on a phone, reached by right-click or long-press, so it is rule 1 of `docs/design/desktop-vs-mobile.md` and law 3 (the long-press equivalent) is already met.
A failure of a menu entry is an inline `AppErrorState` under the message, never a snackbar.

Call controls: one more row in `FloatingDockCard`.
Law 2 of the same document applies: the design system's buttons grow to the touch floor by themselves and the row wraps, so on a phone the same four controls take two lines instead of a hidden fourth.
A failure is an `AppErrorState` in the strip, with retry.

## Library

`slimbots` gets `@bot.message_menu(...)` and `@bot.call_control(...)` decorators, registered with `PUT /bots/ui` on connect, and an interaction context that already carries `kind`, `message_id` and the member, so `ctx.reply_ephemeral` and `ctx.ack` are the same as for a button.

## What this record does not decide

- Menu entries on a member or a channel.
- Text inputs, selects and modals from a menu entry or a control.
- Showing a bot's live state in a call, such as a track title or a playback position, which needs a bot-to-viewers channel this record does not add.
- Menu entries on a webhook message or an ephemeral message.
- Persisting a use across a bot outage.
