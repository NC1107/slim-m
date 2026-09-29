# Push relay audit and follow-ups (2026-09-29)

An audit of what the server and clients need from push notifications against what `slim-m-relay` delivers, after the owner asked whether the relay needed anything for bots or calls.
Line numbers are against `origin/main` before the fixes (slim-m `7be85171`, slim-m-relay `6a11d5b`).

## What shipped from this audit

- slim-m-relay#6 (released as `v0.2.0`): a `call_end` kind, a `security` kind, and a 30 second expiry on call pushes for both APNs (`apns-expiration`) and FCM (TTL).
- slim-m#1479 (server):
  - iOS rings go to the stored VoIP token instead of the ordinary APNs token.
  - Every push path prunes tokens the relay reports as `unregistered`.
  - `call_end` goes out on every ring end, and a canceled ring leaves a missed-call push.
  - Mentions go out as `mention`.
  - New-device sign-ins push `security` to the account's other devices.
- slim-m#1480 (client):
  - `jumpToMessage` no longer auto-joins a voice channel's call.
  - Android handles `call_end` and `security`, and a ring notification times out after 30 seconds.
  - The iOS notification service extension groups by channel with a thread id.

## Gap table

| # | Gap | Verdict | Where fixed |
| --- | --- | --- | --- |
| 1 | An iOS ring needs a `voip` push to `<bundle>.voip`, through PushKit to CallKit | Confirmed. The server sent the ordinary APNs token (`call_ring.rs:177`), which APNs refuses on the VoIP topic, and the client never registers a VoIP token | Server in #1479; client wiring is a follow-up below |
| 2 | Android calls need high-priority data and a full-screen intent | Refuted, already present (`fcm.go:136`, `IncomingCallNotifier.kt:74,89`) | - |
| 3 | Stale rings delivered after the call ended | Confirmed: no APNs expiration and no FCM TTL, which defaults to four weeks | relay#6 |
| 4 | A ring that stops on other devices, and a missed-call push on cancel | Confirmed in part: a canceled ring pushed nothing, and the Android ring notification was ongoing with no timeout | relay#6, #1479, #1480 |
| 5 | New-device sign-in push | Confirmed: `sign_in_alert.rs:39` only published a websocket event | relay#6, #1479, #1480 |
| 6 | Bot and webhook mentions producing pushes | Refuted: webhooks, apps and modules all go through `notify_message` | - |
| 7 | Mentions pushed as plain messages | Confirmed: the server only ever sent `message` (`envelope.rs:291`) | #1479 |
| 8 | A busy channel spamming notifications | Mostly refuted (10 second server debounce, Android replaces per channel); iOS had no thread id | #1480 |
| 9 | Badge counts | Confirmed, not done | Follow-up below |
| 10 | Dead tokens fed back to the server | Confirmed in part: the ring path ignored relay results (`call_ring.rs:115`) | #1479 |
| 11 | A notification tap auto-joining a call (owner report) | Root cause fixed by #1397 in client 0.87.0; the same shape remained in `jumpToMessage` (`message_jump.dart:37`) | #1480 |
| 12 | Android cannot decrypt the sealed envelope | Confirmed, not done | Follow-up below |

## Follow-ups for later

### 1. iOS PushKit and CallKit wiring

This is the only reason an iPhone with the app closed still does not ring.
The code can be written without the owner; confirming it cannot, because iOS kills an app that receives a VoIP push without reporting it to CallKit, and repeated failures cost the app VoIP pushes.
Because every merge ships to TestFlight, build it as a PR and hold it until it has been tried on a real iPhone.

- Construct `VoipPushRegistrar` at launch and send its token to `PUT /push` as `voip_push_token`.
- Decrypt the sealed ring in the Runner (the extension already reads the push key) for the caller name and ring id.
- Implement `CXAnswerCallAction` (join the DM call) and `CXEndCallAction` (decline), and end the CallKit call when the ring ends.
- `VoipCallHandler.swift:161` currently has only `providerDidReset`, and it reads plaintext `caller`/`call_id` keys the relay never sends.
- Tracked in `docs/OPEN-QUESTIONS.md` item 3.

### 2. Apple configuration (owner)

- Confirm the App ID has Push Notifications enabled; VoIP over token auth needs no separate certificate.
- Confirm the prod relay's `.p8` key and `RELAY_APNS_PRODUCTION=true` match the TestFlight build.

### 3. Android on real hardware (owner)

- Ring a killed app. On Android 14 and later the full-screen intent needs the user-granted `USE_FULL_SCREEN_INTENT`.
- Hang up from the caller and check the ring stops within a second or two.
- Check a missed call and a sign-in alert land on the right notification channels.

### 4. Badge counts (product decision)

Nothing sets an app icon badge today.
Decide what it counts: unread mentions only, or every unread channel.
The notification service extension can set `content.badge` from a count inside the sealed envelope, so nothing leaks to the relay.

### 5. The rest of the new-device sign-in alert

- Tapping the alert should open the devices pane.
- A device that was offline at sign-in time should see a notice on its next launch.
- Planka card 1874504444486354259.

### 6. Android previews and tap routing

Android acts on the push `kind` alone and never decrypts the envelope, so it shows no message preview and a tap cannot open the right channel.
Fixing it means giving the FCM background isolate access to the push key.
