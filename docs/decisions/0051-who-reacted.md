# 0051 - who left a reaction is readable on request, never on the wire

Status: accepted, 2026-10-01.

## The report

The owner, from his phone:

> "Is there no way to tell who left a reaction on a message, like hold press the reaction?"

There was not.
The server sent a per-viewer tally for each reaction and nothing else.

## What the record said before

[0009](0009-reactions-pins-polls-reconciliation.md) and [0031](0031-bot-command-registration.md) record the stance: `http::ws::frames` withholds reactor identity from the broadcast frame, and every connection derives its tally at send time with the viewer's blocklist applied.
A precomputed tally fanned out unfiltered once let a live reaction quietly undo a block, so the filter being per viewer and per read is the part that must survive.

## What changed

`GET /messages/{messageId}/reactions/{emoji}` lists the people who left that reaction.

- **Who may ask.** Anyone who may read the message.
  A viewer who cannot read its channel, and a deleted message, get the same not-found answer as an id that never existed, so the route is not a probe.
- **What they see.** The same block filter the tally uses: a reactor the viewer has blocked is left out.
  The list therefore always holds exactly as many people as the count the same viewer was shown.
  A reactor who blocked the viewer is still counted by the tally, so they are still listed.
- **What it returns.** `{ users: [{ user_id }], next_cursor }`, oldest reaction first, 50 per page by default and 100 at most.
  The id is all the server sends.
  The client resolves names, avatars and the bot badge from the members it already holds, which is the project's rule: send the id, let the client resolve.
- **Cost.** Charged to the authed-read rate class.
  No migration: `reactions` already stores who and when.

## What did not change

- Reactor identity is still absent from every WebSocket frame.
  `ReactionsChanged` still carries only counts, derived per connection at send time.
  This route is a per-viewer read, which is the whole difference.
- The block filter is applied in the query, not left to the client, because the client has no way to know whom a count excluded.
- Reactions stay unmoderated by blocking: a blocked reactor's reaction is untouched for everybody else, and the reactor is never told.

## Consequences

- Bots are full principals, so a bot that can read a channel can now read who reacted in it, through this route.
  0031 said a bot cannot see who reacted; that is no longer true on request, and the privacy line it describes now sits at the wire frame rather than at the data.
  Nothing is pushed to a bot unasked.
- Reacting reads as lower commitment than posting, and it is now attributable by anyone in the channel.
  That is what the owner asked for and what Discord does.
  A reaction can still be removed at any time, and removing it removes the person from the list.
- The client surface is rule 3 of `docs/design/desktop-vs-mobile.md` (info about a thing): a bottom sheet below 600, an anchored popover beside the chip from 600 up.
  Holding a chip opens it at any width, and so does a right-click.
  Resting a mouse on a chip shows a tooltip with the first names, which is only a hint: the list is always one hold away, so no touch user loses anything (law 3).
