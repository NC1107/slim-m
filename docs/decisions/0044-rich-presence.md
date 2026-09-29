# 0044 - Rich presence: what someone is listening to or playing

Status: accepted
Date: 2026-09-29

## The ask

The owner, 2026-09-28: "spotify/music integration? (same for games)".

Read as Discord-style activity: a member row and a profile card can say "Listening to X" or "Playing Y".
This record fixes the privacy model, where activity comes from, the wire shape and what the server keeps, before any source beyond the first is built.

## Privacy model

- **Opt-in, off by default.**
  Nothing is read or sent until the person switches a source on in Settings (Profile > Activity).
- **One switch per source.**
  Only listening exists today; games get their own switch later, so turning on music never turns on game detection.
  A source that is off is never started: an opted-out device does not open a D-Bus connection or scan a process list.
- **Visible only to people who can already see your presence.**
  The server resolves an activity through the same function that resolves a status (`presence::status_for`).
  It is dropped whenever the status a viewer would read is offline.
  That covers appear-offline (hidden), a closed socket, and an unknown account.
  A hidden user still sees their own activity, the same asymmetry their status has.
- **The client checks too.**
  It sends nothing while it knows the caller is hidden, and clears what it sent when they hide.
  This is a second lock.
  The client cannot always know the visibility at launch (a known gap in `presence_controller.dart`), so the server rule is the one that holds.
- **Cleared on pause, stop and quit.**
  A paused player reports nothing.
  A closed socket drops the activity because it lives on the connection.
- **Nothing is inferred silently.**
  Detecting a game from running processes is the invasive part of Discord's design, so it stays behind its own explicit switch and an allowlist (below).

## Sources compared

| Source | Credentials | Works on | Verdict |
| --- | --- | --- | --- |
| Linux MPRIS over D-Bus | none | Linux desktop, any player that exposes `org.mpris.MediaPlayer2.*` (Spotify, browsers, mpv, VLC) | First slice. Local, private, no third party. |
| Windows SMTC (`GlobalSystemMediaTransportControls`) | none | Windows 10+ desktop, any app that registers a media session | Next. Needs a Windows binding; a separate card. |
| macOS Now Playing | none | macOS | Restricted. The MediaRemote framework is private and Apple has been closing it. Revisit only with a supported API. |
| Spotify Web API | an OAuth app registered by the owner | any platform incl. phones | Later. Only the Spotify account, needs a token store and a refresh path. |
| Game detection | none | desktop | Later, opt-in, allowlist only. |

Why MPRIS first: it needs no account linking and reads exactly what the person is already playing, on the machine the owner develops on.
A phone has no equivalent, which is what Spotify linking would cover later.

### MPRIS details

The client polls the session bus every five seconds and picks the first player whose `PlaybackStatus` is `Playing` and whose metadata names a title.
Polling was chosen over subscribing to `PropertiesChanged` because a few seconds of lag is fine for presence and one loop is simpler than tracking players appearing and vanishing.
The package is `dbus` (pub.dev, BSD-3-Clause, already resolved transitively at 0.7.14), which is on `deny.toml`'s allowlist.
It is imported only through a conditional import so web builds never compile it, and the source is absent (not shown dead) on other platforms.

### Game detection (later)

A process-name allowlist shipped with the client, matched only when the "playing" switch is on.
The person can see the list, and nothing outside it is ever reported or logged.
Steam's local state (the `registry.vdf` "RunningAppID" key on Linux and Windows) is a cheaper, more precise signal for Steam titles and avoids scanning processes for those.
The CS2 night bot card proposes opt-in Steam presence for one game; this mechanism is what it would sit on, so Steam presence is not built twice.

## Wire shape

An optional `activity` object on presence, in both `PresenceStatus` (`GET /presence`) and the `presence.changed` frame:

- `type`: `listening` or `playing`
- `title`: at most 128 characters
- `subtitle`: optional, at most 128 characters (the artist, for music)
- `started_at`: optional, epoch milliseconds

Text with control characters or direction-changing marks is refused, not trimmed, so what viewers read is exactly what was sent.
Two routes set it: `PUT /presence/activity` and `DELETE /presence/activity`.

**Art is not in the first shape.**
When it is added it will be an attachment or a hash the server already holds, never a URL a client supplies and the server or other clients fetch.
A URL field would let one member make every other client (or the server) request an arbitrary address.
Spotify's cover URLs would be fetched by the sender's client and re-uploaded, or skipped.

## Server storage

Ephemeral only, in memory, on the sender's `PresenceTracker` entry.
No migration and nothing on disk.
It dies with the user's last connection, which also means a reconnect starts empty and the client resends.
A second device connecting does not clear it.

## Rate limits

A new traffic class, `presence_activity`: burst 6, refill one per five seconds, per account.
A skipping listener can change track every few seconds, and each accepted write fans out to every connected member.
An unchanged repeat is accepted but not re-announced.

## Core, not a bot or a module

Activity on the member row and card is core presence.
A bot can only post messages, and a module only draws what it is given, so neither can put a line on a member row.
By [0035](0035-module-or-bot.md) it is a host surface.

## What the owner must provide for Spotify

Spotify is not built here.
When it is, the owner needs to:

- register an app in the Spotify developer dashboard and choose the redirect URIs for each client platform
- hand over the client id, and the client secret if the flow needs one (the PKCE flow does not, and is preferred)
- decide whether a token lives on the device only, or on the server (which would make the server hold a third-party credential per member)
- accept Spotify's developer terms, including the quota mode an unreviewed app runs under (a small allowlisted user list until Spotify approves it)

## Follow-up cards

Windows SMTC, macOS Now Playing, Spotify linking and game detection are separate Backlog cards linked to this record.
