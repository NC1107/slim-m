# 0034 - Read state across devices: the marker is per account, and push consults it

Status: accepted
Date: 2026-09-28

## The owner's request

> "make sure if im viewing messages on desktop, I dont get notifications about them on mobile"

> "me sending messages on mobile while my desktop is on, also shouldnt result in an unread message badge on a channel"

## What was already true

The read marker (`read_states.last_read_seq`) is per account and per channel, monotonic, and `PUT /channels/{id}/read` advances it.
So the storage was never per device.
Two things were missing around it.

First, nothing told the account's other sessions that the marker moved.
Each client learned its own marker from its own write, and everyone else's only on the next full refresh.
A message sent from a phone therefore left the desktop badge up until something refetched.

Second, sending did not touch the marker at all, and push never looked at read state.
The only suppression was a push device's own foreground report, which says nothing about a different device that has the channel open.

## Decision

Moving the marker announces it.
`PUT .../read` and a message send both go through one helper that advances the marker and publishes `read_state.changed` with the stored `last_read_seq`.
The frame is delivered only to the owning account's own sockets and is withheld from everyone else, so it clears a badge on every device and is not a read receipt.
Receipts stay deferred.
Applying it is a `max`, so a late frame can never un-read a channel.

Sending advances the author's own marker to the new message, on the same reasoning as Discord and Slack: you cannot have unread messages in a channel you just posted to.
This also moves the marker past anything the author had not yet read in that channel, which is the same trade those apps make.
It is best-effort: the message already landed, so a failure to move the marker is logged and does not fail the send.

Push drops a recipient in two cases, decided after `message_recipients` so its permission, block, preference and schedule rules are untouched.
This step only ever removes people.

- The recipient's marker already covers the message's seq.
  That is what a device that read it, or a send from another device, leaves behind.
- One of the recipient's connections reports the channel open and focused right now.
  This covers the window before that device has advanced the marker for a message that has only just landed, which the marker check alone cannot.

The second signal is a new client frame, `viewing`, carrying the channel ids the connection has open in a focused window.
It replaces the connection's previous report, is held in memory only, and lapses after 90 seconds, so a client that is suspended without closing its socket cannot silence push for long.
Clients re-send it about every 30 seconds while a channel is open, on focus changes, and after a reconnect.
An unfocused window or a backgrounded phone reports nothing, so it never silences the account's other devices.

## Privacy

The report is read only by the push path, for the reporting account's own push, and is never broadcast.
It does not touch presence, so a hidden presence stays hidden and nobody learns which device is active.

## What this does not do

A channel that is mounted but hidden behind another screen on a phone still counts as open while the app is focused.
That only suppresses that account's own push for that channel, for as long as the app is in front.
