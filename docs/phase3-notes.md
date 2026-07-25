# Phase 3 working notes

## Provider credentials

Obtained 2026-07-24, verified against the live providers rather than by inspection.

### Android (FCM)

Firebase project `slim-m`, created fresh on the free Spark plan.
Google Analytics and Gemini-in-Firebase were both declined at creation, because neither is needed to send a push and both widen what Google sees of a messaging product.
FCM v1 API is enabled.

The service account key lives at `~/.secrets/slim-m/fcm-service-account.json`, mode 600 in a 700 directory, deliberately outside the repo.

Proof it works: the key mints a Bearer token against the `firebase.messaging` scope, and a send to `v1/projects/slim-m/messages:send` is rejected with 400 INVALID_ARGUMENT on `message.token` rather than 401 or 403.
That distinguishes a working, authorised credential from one that merely parses.

### iOS (APNs)

Team ID `76S78SUWVM`, key ID `AY9T3ZH9JX`, stored at `~/.secrets/slim-m/apns-auth-key.p8`.

Registered as team scoped across all topics, sandbox and production.
Team scoping was chosen deliberately: a topic specific key needs a bundle identifier, and at the time no iOS target existed, so picking one would have frozen a permanent identifier while the product name was still undecided.
Apple's own note on the key is "one key is used for all of your apps".
Both the environment and the restriction type are fixed at creation and cannot be changed afterwards.

Proof it works: the key parses as an ECDSA key, signs a JWT from the key ID and team ID, and a push to the sandbox gateway returns 400 BadDeviceToken rather than 403 InvalidProviderToken.
A 403 is what a wrong key, key ID, or team ID produces, so a 400 about the device token is what confirms the triple is right.

## Bundle identifier

`top.npcserver.slimm`, on iOS and Android alike.

It follows the existing `top.npcserver.checkin` convention rather than a hyphenated form.
A hyphen is legal in an iOS bundle identifier but not in an Android `applicationId`, so a hyphenated choice would have forced the two platforms apart for no benefit.
The identifier is not tied to the product name, which is still undecided: the App Store display name is a separate field and stays free to change.

`flutter create` generated three different identifiers of its own, `top.npcserver.slimm_app` on Android, `top.npcserver.slimmApp` on iOS, and the untouched `com.example.slimm_app` on Linux.
All three were corrected to the registered one.

## Bug found while verifying: dead tokens were never pruned

`internal/fcm/fcm.go` treated only `UNREGISTERED` as a dead token.

A malformed or corrupt registration token does not return `UNREGISTERED`.
The live API returns 400 with `errorCode: INVALID_ARGUMENT` and a field violation on `message.token`, which mapped to `StatusError`.
Since `StatusError` reads as "worth a retry", the server would keep that token forever and re-send to it on every notification.

The first fix for this did not work, which is worth recording because the failure was invisible.
The error body was read through `io.LimitReader(resp.Body, 512)`, and FCM pretty-prints by default, so the real body is 571 bytes.
Truncating at 512 cuts the JSON mid-document, `json.Unmarshal` returns "unexpected end of JSON input", and the token falls straight back to being retried forever.
A minified test fixture passes even with the bug present, since it fits under the old cap whole.
The regression test therefore uses the exact pretty-printed body, and the read cap is now 16 KiB.

## Second bug, introduced by the fix for the first

Adding `last_seen_at` to the relay's `tokens` table to support pruning shipped an `ALTER TABLE ... DEFAULT 0`.
On an already-deployed relay that backfills every existing row to epoch 0, so the first prune sweep deletes the whole table.
Those rows are the token-to-key bindings that stop one key pushing to another key's device, so losing them is a safety regression, not just lost data.
The migration now backfills pre-existing rows to the current time, giving them a full retention window, and a test builds the pre-upgrade schema by hand and asserts the binding survives.

## Local build note

Android could not be built on the development host at first: only a JRE was installed, and Fedora 44 packages no LTS `-devel` JDK, so Gradle failed with "does not provide the required capabilities: [JAVA_COMPILER]".
A user-local Temurin 21 at `~/.local/jdk/jdk-21.0.12+8` resolves it without root, wired in with `flutter config --jdk-dir=...`.
JDK 21 rather than the packaged 25, because that is the LTS the Android Gradle Plugin supports.
