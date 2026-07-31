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

## 7. The next client build wipes its own message cache, once

Message reconciliation landed on 2026-07-31 (#235, #236, #237, #238), closing the debt where an edit or a delete made while a client was offline never reached it.

Part of that is a drift schema bump to v7 that **drops every cached message and rewinds the sync cursor**, on every device, the first time it runs.

That is deliberate and it is not avoidable.
Edits and deletes made before the server had an op stream to record them in are unrecoverable by any mechanism: no cursor reaches behind the first op ever written, so a message this cache holds a stale copy of would stay stale forever.
Dropping the cache once is the only thing that closes that epoch.

*What you will see:* open the app after updating and each channel refetches its newest 50 messages.
Anything older is refetched by scrolling, exactly as it is on a fresh install.
Channels, read markers and unsent drafts are untouched; only the message cache goes.

*Not a question, just something you should not have to diagnose in the moment.*
If it looks like data loss rather than a refetch, that would be a real bug and worth reporting.

## 8. Nothing verifies reconciliation on a real pair of devices

Every property of the op stream is covered by unit and integration tests, and the mutation tests confirm each one can fail.
What none of that proves is the thing the feature exists for: edit a message on your phone while your desktop is closed, reopen the desktop, and see the new text.

`scripts/e2e.sh` drives two browsers and would be the natural place for it, but it holds both clients open throughout, so it cannot currently express "one client is away while the other writes".

*Question:* worth growing the e2e harness to close and reopen one client mid-run, or is confirming it by hand across your own two devices enough?

## 9. The client release PR is stuck, and the fix is a merge rather than a repair

Server 0.21.0 is released and deployed; the live instance reports it, so migration 0027 has run against production.

The matching client release ([#229](https://github.com/NC1107/slim-m/pull/229), 0.17.0) is **conflicted and was left that way deliberately**.

What happened is understood rather than guessed: release-please only refreshes a component's standing PR when that component has new releasable commits.
Nothing client-facing merged after #238, so it left its own branch untouched while merging the server release moved `.release-please-manifest.json` underneath it.
The conflict is on that file plus `client/CHANGELOG.md` and `client/pubspec.yaml`, all three generated.

It was not forced, because every available shortcut (hand-resolving, deleting the branch, editing the changelog) means editing generated files by hand, which `CLAUDE.md` forbids and which this project's own notes flag as something to watch rather than push through.

*What unsticks it:* merging **any** client-affecting change to main. release-please then regenerates the PR cleanly and it becomes mergeable again.
Until that happens the message reconciliation work is on the server but not on any of your devices.

*Question:* if this recurs often enough to be annoying, the alternative is the manual tag-based release flow already listed in section 6, which has no standing PR to go stale.

## 10. An e2e run can silently exercise last week's code

`E2E_REBUILD=1` rebuilds the client from whatever the working tree holds, and nothing in the harness notices the tree is behind `origin/main`.

This cost a full rebuild cycle on 2026-07-31: an e2e run that looked thorough, and passed 19 of 20 scenarios, was built from a checkout predating the whole reconciliation series - the tree had been fetched but never pulled, so it contained no `message_ops_sync.dart` and no migration 0027.

The failing scenario was the new reconciliation one, which is the only reason it was caught at all.
That turned out to be a useful accident (it is a real mutation test: the scenario fails when the feature is absent, and fails on its own assertion rather than on a timeout), but the harness should not depend on luck for this.

*Suggested guard, not built:* print `git rev-parse --short HEAD` at the top of a run and say plainly when it is behind `origin/main`.
It is three lines in `scripts/e2e.sh` and it would have turned a rebuild cycle into a line of output.
Left as a suggestion rather than done, because it changes how every run reports and that is worth a moment's agreement first.

## 11. How long does a canvas live? (owner's own question, undecided)

Raised while using the product on 2026-07-31, and recorded here because it is a product decision with schema consequences rather than something the next contributor should settle by picking one.

> unsure how to handle canvases, like are they forever spaces, or is it like teams where every meeting is a new meeting and chat and the canvas changes after each meeting and is just an artifact or something, or should it persist for as long as the call exists, and people clear it as they need or save/export it as they need

Three models, none chosen:

1. **Permanent per channel.** What ships today: `canvas_objects` is keyed per channel with no notion of a session, and the op stream is keyed the same way.
2. **Per call, becoming an artifact.** Each call starts a fresh canvas and the previous one is kept as something you can open but not draw on. Needs a session id on every object and op, and a decision about where artifacts are listed.
3. **Lives as long as the call**, cleared or exported by hand.

The reason this cannot be deferred indefinitely: 1 is the only one the current schema expresses, and 2 and 3 both need a session key threaded through `canvas_objects`, `canvas_ops` and every read, which is a migration over a table that will have real content by then.
The longer the canvas is used, the more expensive the other two become.

*Question:* which of the three, or something else? The `save/export` half is a separate feature in every model and does not need answering at the same time.
