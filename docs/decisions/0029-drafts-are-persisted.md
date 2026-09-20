# 0029 - Drafts are persisted, and are the one local-only table

Status: accepted
Date: 2026-09-19

## The ask

An unsent composer draft was held in memory for the life of the session.
`channel_drafts.dart` said so outright, and said why: the report it was built for was about switching channels, and in-memory covered that with no migration and no new place a sign-out has to remember to wipe.

That was an honest scoping call against its report.
It is wrong about the loss, for a reason the original framing did not cover.

## What changed the answer

**On a phone, a restart is not something anybody chose.**

The original reasoning treats "restarting the app" as a deliberate act, and weighs losing a draft against it accordingly.
But the common case on a phone is the OS reclaiming a backgrounded app, which is indistinguishable from a restart to the person who reopens it and finds their words gone.
They did not restart anything. They switched to another app and came back, which is the same shape as switching channels and back - the case the draft feature already exists to cover.

So the distinction the in-memory decision rested on does not survive contact with how phones work.

## The decision

Drafts are written to the local drift database, one row per channel, and restored on launch.

Three things make that safe to do rather than merely possible:

- **The in-memory map stays authoritative.** A composer opening a channel needs an answer in the same frame, not a future. The database only ever catches up behind the map, and a restore fills channels the map has nothing for rather than replacing it - somebody typing during the restore is stating a newer intent than the row being read.
- **The write is fire-and-forget.** A draft is worth saving and is not worth making a keystroke wait on a disk to find out whether it was. A failed write costs exactly the words a crash would have cost anyway; a blocking write would cost every keystroke.
- **The rows go on sign-out**, in `MessageStore.clear()`, with the rest of the local cache.

## The part worth writing down

**This is the first table in the local store that is not a cache of server state**, and that changes which debts apply to it.

`local_schema_reconciliation_test.dart` is a tripwire on exactly this: a new local table usually means something server-owned has started being cached, which reopens the reconciliation debt `CLAUDE.md` records - an offline client never learning about a change it missed.

A draft cannot have that problem. The server never has one, so there is no authoritative copy for a local one to drift from, and nothing a reconciliation could reconcile it against.
What it needs is the opposite guarantee, and the opposite guarantee is the sign-out wipe: the words are real, only this device ever held them, and they belong to the account that typed them.

So the tripwire now sorts a new table into one of two kinds rather than refusing all of them, and whoever adds the next one has to say which it is.

## What is deliberately still not persisted

A reply-in-progress and a staged attachment.

`ChannelScreen` already clears a reply target on a channel switch, because a reply is scoped to the conversation it was started in, and `Composer` clears a staged attachment the same way.
Restoring text while a stale reply or attachment silently rode along, still pointing at the channel it came from, would be worse than restoring nothing.
That reasoning is unchanged by this record; it is the same reasoning, applied to a restart instead of a switch.
