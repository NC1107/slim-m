<!-- SPDX-License-Identifier: Apache-2.0 -->
# Open questions for the owner

Things an autonomous run could not settle on its own, accumulated as they came up.
Each entry says what is blocked, why it needs a person, and what the run did instead.

Nothing here is a request for permission to do ordinary work.
These are the cases where proceeding under any assumption would be guessing, or where the check genuinely needs hardware or an account only the owner holds.

**Started 2026-07-31.**
Newest sections at the bottom, so the order is the order they were found.

---

## 1. Device confirmation nobody here can do

Three changes shipped this week are correct as far as unit tests and traced library source can establish, and none of them can be confirmed without hardware in your hands.
This matters more than it normally would, because an iOS screen-share fix was recorded as done on 2026-07-29 on exactly that basis and a real device later disproved it.

- **Screen share on iOS** (client 0.16.0 and later). Start a share from a call and confirm it survives past the first few seconds rather than raising "Screen Recording has stopped".
- **CallKit background execution** ([#212](https://github.com/NC1107/slim-m/issues/212), merged in #231). Start a call from the app's own UI, background the app, and confirm the call keeps running and appears in the Dynamic Island.
- **The camera pre-toggle** (#231). This box has no webcam, so the capture path itself has never run.

*What the run did instead:* covered each with unit tests against fakes, and said plainly in every PR body that device confirmation is outstanding rather than calling them done.

## 2. Android has never had a call held on it

`RECORD_AUDIO` was missing from the Android manifest from the day voice shipped until #231, so a call on Android could never have captured audio.
Nothing caught it because no Android device has ever been available, and no CI check can see a missing runtime permission.

That permission is declared now, but the fix is unverified, and the same blind spot still covers the whole Android call path plus the last Phase 3 exit criterion (a real backgrounded Android device receiving a content-free push).

*Question:* is an Android device likely to be available at some point, or should the Android call path be treated as unsupported and said so in the docs rather than shipped untested?

## 3. `VoipPushRegistrar` is dead code, and waking it up is risky

[#230](https://github.com/NC1107/slim-m/issues/230). `VoipPushRegistrar` is declared in `VoipCallHandler.swift` and constructed nowhere, so the inbound VoIP push path does not run at all, despite a passing XCTest suite that has been guarding it.

This was deliberately not fixed autonomously. Constructing it turns a dormant path into a live one that must be correct on the very first push, because iOS terminates an app that receives a VoIP push and does not report a call synchronously. The failure mode is the app being killed, on your phone, with no local way to test it first.

*Question:* do you want this wired up, accepting that the first confirmation is a real push to your own device?

## 4. Things only your accounts can do

- **Play internal testers.** There is no Play Developer API credential anywhere on this box; `~/.secrets/slim-m/` holds only the Firebase service account, which is scoped to messaging. Tester lists live in Play Console and each tester must accept an opt-in link.
- **Reviewer protection on the `release` and `testflight` GitHub Environments.** They exist and are ungated.
- **An optional GPG signing secret** for the Linux client checksums.

## 5. Continuous deployment now reaches production without a human

Since #228, a merge to main touching `crates/**` pushes `latest`, and Watchtower deploys it to `https://slim.npc-server.top` on its own.
That was your explicit instruction and it is working, but it is worth stating once in a durable place: the safety property is now "main is always good" rather than "somebody chose to release".

*Question:* if that turns out to be too loose, the cheap correction is to keep pushing the sha and `main` tags on every merge but move `latest` back to tagged releases only. Say the word and it is one line.

## 6. Decisions left open in the knowledge base

Carried forward from `CLAUDE.md`'s own owner list, unchanged by this run:

- Whether to keep release-please's standing release PR or move to manual tag-based releases.
- Where, if anywhere, a flatpak build should be published once the manifest exists.
