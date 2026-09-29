<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->
# Phone tester checklist

Steps to run with a TestFlight (iOS) or Android build, written for someone who is not a developer.
`docs/BETA-TESTERS.md` is the briefing to read first, and `docs/INSTALL.md` covers getting the app on the device.

None of the paths in sections 1 to 4 has ever been confirmed on a real device, so a report on them is the first confirmation this project gets.
Do them in order and stop at the first one that misbehaves if it blocks the rest.

## What every report needs

Copy this block into each report, one per section that went wrong or right.

- Device model and OS version (Settings, General, About on iOS; Settings, About phone on Android).
- App version (Settings, then the version line at the bottom).
- What you did, in order.
- What happened, with the exact wording of any error.
- A screenshot or screen recording.
- Whether it happened again on a second try.

A "worked" report matters as much as a "broke" one.
Send reports where the owner said to, not in a chat that scrolls away.

## Before you start

You need two accounts and two devices.
Device A is the phone under test, signed in as account A.
Device B is anything else (desktop or another phone), signed in as account B.
Both accounts must be in the same community, and account A must have allowed notifications for the app.
Invites are `slimm://` links or a bare code plus the server address, never `https://`.
Voice may not connect outside the server's own network, so join Wi-Fi on the same network if a call will not connect.

## 1. Incoming call rings, and answering from the lock screen (iOS)

Setup: lock device A and leave it on the lock screen.

1. From device B, start a direct message call to account A.
2. Watch device A for ten seconds.
3. Answer from the lock screen.
4. Talk for a few seconds, then hang up from device A.

Expected: device A shows the full-screen incoming call screen or banner with B's name and rings, and answering connects audio both ways.
While the call runs, the app shows in the Dynamic Island or the green status pill.

Known: the inbound VoIP push is deliberately not wired (`docs/OPEN-QUESTIONS.md` item 3, issue #230).
So a ring with the app fully closed may not appear, and that is a known gap, not a new bug.
Report which of these you saw: full ring, a plain notification, or nothing.

Also check the other direction once.
Start a call from inside the app on device A, press the home button, wait a minute, and confirm the call is still going and audio still flows.

## 2. Lock-screen push preview (iOS and Android)

Setup: lock device A.

1. From device B, send account A a direct message with a recognisable sentence.
2. Look at device A's lock screen.

Expected: the notification names the sender and shows the sentence.
Not expected: a generic "New message" with no name or text.

If it shows "New message", report it anyway.
Two different causes look identical from outside, so also say whether the phone had been unlocked since it last restarted.

## 3. Push for a call nobody answered

Setup: lock device A and let it sleep for a minute.

1. From device B, call account A.
2. Do not answer on device A, and let the ring time out.
3. Look at device A.

Expected: a notification arrives for the missed call, and opening it lands on the direct message where the call shows as a missed call row.

Report whether the notification arrived at all, how long after the ring ended, and what it said.

## 4. Long-press menus

Do each on device A with one finger and a half-second hold, without lifting.

1. A message in a channel: hold it.
   Expected: a menu with message actions (reply, copy, react and similar) opens, and lifting the finger does not pick an item by itself.
2. A member row in the member list: hold it.
   Expected: the member's menu opens.
3. A canvas object: open the Voice Canvas, pick the Select tool, then hold an object and hold an empty spot.
   Expected: an object menu on the object and a different menu on empty space.
   With any drawing tool armed, holding should draw or place, not open a menu, and that is intended.
4. A call tile while in a call: hold a participant.
   Expected: a quick-actions menu including a volume control.

Report any hold that did nothing, opened the wrong menu, opened one and immediately closed it, or drew a stray mark on the canvas.
Also note whether the menu sat off-screen or under the keyboard.

## 5. Phone flows changed this sprint

These were only exercised in tests and screenshots.
If your build predates a fix, the notes below say which pull request it is, and you can skip that item.

**Landing back on the channel after hang-up (#1410).**
Open a text channel, join a voice channel, then hang up.
Expected: you land on the last text channel you were reading, not on an empty screen or the voice channel.

**Call bar above the keyboard (#1412).**
In a call, open the chat and tap the message box so the keyboard appears.
Expected: the compact call bar sits above the message list and stays visible, and nothing overlaps the keyboard.

**Permissions grid on a phone (#1407).**
As an admin, open a channel's permissions.
Expected: role names stay pinned at the left while you scroll sideways, a hint shows there is more to scroll, cells are readable, and Save applies the change and shows it after reopening.

**Read state across devices (#1408).**
Sign in on desktop and the phone as the same account, then have another account post in a channel.
Read it on desktop and wait a few seconds.
Expected: the phone does not buzz for that message, and its unread badge clears.
Report if the phone still notified after you had read it.

**Pre-muted voice channels (#1411).**
As an admin, mark a voice channel as joining muted, then join it from the phone.
Expected: you enter already muted, the mute control shows that, and you can unmute yourself.

## 6. Screen share and camera (iOS)

Start a screen share from a call and keep it up for a full minute.
Expected: it keeps going, and other participants keep seeing your screen.
Not expected: "Screen Recording has stopped" within the first few seconds.

Then turn the camera toggle on in Voice Settings and join a call.
Expected: your video appears for the other participant.

## 7. Android

Android has never had a call held on it, so a first call is the test.

- Sections 2, 3, 4 and 5 apply as written.
- Section 1: incoming calls on Android arrive as a normal call notification, not the iOS call screen.
  Report whether it rang, and whether answering connected audio.
- On the first call the app should ask for microphone permission.
  Report if it never asked, or if you granted it and the other side still heard nothing.
- Background the app during a call for a minute and report whether audio continued.
