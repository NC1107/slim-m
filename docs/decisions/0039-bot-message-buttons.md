# 0039 - Buttons on bot messages, and private answers to a press

Status: accepted, implemented
Date: 2026-09-29

## The ask

The owner, 2026-09-24: bot buttons and private replies first.
The gap analysis of the same day ranked this the biggest ceiling on what a bot can do, because no client library can fake a button.
It unlocks confirmations without retyping a command, a casino hand with Hit and Stand shown privately, role pickers and pagination.

This record stacks on 0037, which fixed the private-reply half and explicitly left room for this: a private answer to a press reuses the same primitive with the interaction as the anchor and the presser as the recipient.

## What it is

- A bot message can carry `components`: up to 5 rows of up to 5 buttons.
  A button has a label, a style (`primary`, `secondary`, `danger`, `link`), a `custom_id` for the non-link styles, a `url` for link buttons and a `disabled` flag.
- `POST /channels/{c}/messages/{m}/interactions` is a press.
  The presser chooses the interaction id, so a retry is the same press.
- The bot receives an `interaction.created` frame over the ephemeral hub class.
  It answers with a private reply, a replacement of the buttons, or an explicit ack, and the presser receives `interaction.answered` when it does.
- `PUT /channels/{c}/messages/{m}/components` replaces or clears the buttons on the bot's own message.

## Decisions

### Components live in a side table, as one JSON document

They are a side table, never a column on `messages`, following 0030 and the memory of what a column costs ten SELECTs.
Unlike an embed they change after the fact, so they are one validated JSON document per message rather than normalised rows nothing queries by.
`crate::components::validate` is the only writer of the caps, and the same shape serves the wire and storage.

They ride every path a message does.
The send response, the list, `/sync` and search go through `message_enrich::with_reactions`, and the live `message.created` frame carries them on the event.
An edit of the text does not touch them, and the edit frame omits them, so the client keeps what it holds.
A change of buttons is its own event, `message.components`, carrying the whole current list, like a poll tally, so a client that missed a frame converges on the next one or on a reload.

### The caps

5 rows, 5 buttons a row, an 80-character label, a 100-character `custom_id` unique within the message, a 512-character http or https `url` on link buttons only.
They copy Discord's so its bots port, and they are enforced by the server on send and on replace.
A link button takes no `custom_id` and cannot be disabled, because it never reaches a bot.

Only a bot may send them.
Anyone else gets a 403 rather than the silent discard embeds use: the caller of this field is a program, and a dropped button set would never be noticed.

### A press names the presser

0031 withheld the invoker's identity from advertised commands on purpose.
A press is different in kind: the bot cannot answer a press without knowing who pressed, and the presser chose to address that bot by pressing its own button.
So `interaction.created` carries the presser's id and display name, and it goes to the owning bot's connections only.
No other bot, no other member and no administrator receives it.

The route refuses, with the same 404, a press on a message that is not a live bot message, on a button that does not exist, is disabled or is a link, and on a bot that has left or cannot view the channel.
The presser needs `VIEW_CHANNEL` and cannot be a bot, so bots cannot drive each other.
A press is charged to its own rate limit class per presser, tighter than an ordinary write, since each one wakes a bot that may do real work.

### The interaction is a short-lived row

It is the one thing stored, and it holds no content: the ids, the `custom_id`, whether it was answered, and how many private replies it has spent.
It lives 15 minutes, which is also how long it can be answered, and is swept with the token sweep.
The ids carry no foreign keys, so the row never joins the account-deletion audit for something that expires on its own.

The alternative was an in-memory table.
It would have needed a new `AppState` field in every test that builds one, and it would lose a press across a restart for no gain.

### Private replies to a press

The request names its anchor in one of two fields, and exactly one must be present: `in_reply_to_id` for a message under 0037's rules, or `interaction_id` for a press.
They are separate ids with separate resolvers in `http::ephemeral_anchor`, and neither can be read as the other.
This is a fix from the security review.
The first draft reused `in_reply_to_id` for both, resolving a press first, so a member could press a button with the id of someone else's message and redirect a bot's legitimate whisper to themselves, or make it fail for everyone else.
Now a press whose id already names a message is refused with a 409, and a press that is not the caller's is a 404 whichever field it is sent in.
A press needs no addressing check, because pressing the bot's own button is the addressing.
The press case requires that the caller is the bot the press went to, that it is in the same channel, and that the press is still open.
It spends from the same per-anchor budget as a message anchor, three private replies, so a single press cannot become a standing channel to the presser.
The delivery path, the frame, the tray and the block rules are unchanged.

### What a button may say

A label and a `custom_id` are refused if they hold control, zero-width or bidi characters, using the same test as display names, so a label cannot reorder or hide its own text.
A link button's url is parsed, must be http or https with a host, cannot carry a username or password, and is stored in its normalized form.
The raw text is checked first, because the parser silently drops tabs and newlines, and a url the parser had to forgive (`https:///host`, a backslash) is refused rather than shown as something else.
The client shows the destination host under a link button, so a label cannot pose as a different site.
A change of buttons that names a press checks the press before it changes anything, so a bad id does not leave the buttons half-updated and broadcast.

### Acknowledging

The presser's button shows as pending until the bot answers.
An answer is any of a private reply to the press, a replacement of the buttons that names the press, or a bare ack.
The server marks it once and sends `interaction.answered` to the presser only.
The client fails the button after about five seconds of silence and says so on that message, with a retry that presses again.
Silence can mean the bot is down, offline, slow or that the frame was lost, and the client cannot tell which.

### Delivery is best effort

The press and its answer ride the ephemeral class, so a subscriber that lags past the channel capacity can lose one, and a bot that is offline never sees it.
That matches how the client treats it: pending, then a visible failure the member can retry.
Nothing here needs a catch-up path, and putting it on the durable class would let one lagging bot close connections over something already time-boxed.

## Client

A row of buttons under the message's text, and the embeds.
Styles map to the design system's button roles; a disabled button, one whose bot was removed and one on a message that no longer exists render disabled.
A press shows a pending state on that button, and a failure is an inline `AppErrorState` on the message, never a snackbar.
Layout follows width, not platform: the row wraps.

## Library

`slimbots` gets buttons on `send`, an `on_interaction` decorator keyed by `custom_id`, `ctx.reply_ephemeral` on an interaction context, and `edit_components` and `ack` helpers.

## What this record does not decide

- Select menus, text inputs and modals.
- Buttons on webhook messages or on an ephemeral message.
- Persisting presses across a bot outage.
- Letting a bot see who has pressed a button in aggregate.
