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

## 9. ~~The client release PR is stuck~~ (closed 2026-08-01, and the diagnosis held exactly)

**Closed.** Client **0.18.0** is released and on TestFlight.
The fix was the one predicted below and nothing else: merging a client-affecting change ([#259](https://github.com/NC1107/slim-m/pull/259)) made release-please regenerate the standing PR, which went from `CONFLICTING` to `MERGEABLE` within about two minutes and merged cleanly, with no generated file touched by hand.
The reconciliation work is now on your devices as well as the server.

The *question* at the end is still live, and is now better informed: this recurred twice in two days.
If it happens a third time the manual tag-based flow in section 6 is worth taking seriously rather than waiting it out again.

The original entry follows, kept because the reasoning is what made the fix predictable rather than lucky.


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

~~*Suggested guard, not built:*~~ **Built 2026-08-01.** `scripts/e2e.sh` prints the commit it is building from, warns by count when the tree is behind `origin/main`, and notes an uncommitted working tree.
Done without waiting for agreement after all, on the grounds that it only adds output: it changes no behaviour, refuses nothing, and cannot fail a run that would otherwise pass.
It deliberately does **not** refuse to run when behind, because working from a deliberately older tree is a legitimate thing to do (that is how the reconciliation scenario got mutation-tested), and a guard that blocks it would be worked around rather than heeded.

*What is still open:* nothing here notices that the **web build** is older than the tree, which is a different staleness and the one `E2E_REBUILD` exists for.
A run without that flag reuses a cached build, so the commit this now prints is the commit of the *checkout*, not necessarily of the bundle being exercised.

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

## 12. Making an autonomous run actually span a week needs one decision from you

The standing instruction was to iterate for a week with no interference.
A single session cannot span a week, and the in-session scheduler (`CronCreate`) is session-only: it dies the moment the session ends, so it does not either.

The mechanism to do it properly exists and was verified on 2026-07-31: `claude` is on PATH at `~/.local/bin/claude` and takes `-p` for non-interactive runs, so a system crontab entry could resume the loop daily.

**It was not set up, deliberately.** An unattended run needs `--allow-dangerously-skip-permissions`, since nobody is there to approve tool calls, and that produces this chain:

> cron -> agent with permission checks disabled -> merges to `main` -> Watchtower deploys `latest` -> the live instance at `slim.npc-server.top`

plus TestFlight and Play builds from any `client-v*` tag it cuts.
For seven days, unobserved.

Every individual link is already how this project works and is your own deliberate setup.
What is new is removing the human from the loop *and* the permission prompts at the same time, which is different from an observed session where each step is seen as it happens.
The blast radius if a run goes wrong is your live deployment and your store builds, and neither is quick to walk back.

*Question, and it is a one-word answer:*

- **Yes** - and the crontab line is roughly `23 9 * * * claude -p "<the loop prompt>" --allow-dangerously-skip-permissions >> ~/.cache/slimm-autorun.log 2>&1`, with the loop prompt already written (it is the `CronCreate` job from that session).
- **Yes, but not to production** - the same thing with the release PRs left unmerged, so a person still cuts every release. This is the middle option and is probably the right one: the work still happens daily, and the only thing waiting on you is the button that ships it.
- **No** - and the honest consequence is that "for a week" means "resume it when you next open a session", which is what happens today.

The middle option is the recommendation.
It keeps the deploy decision human while losing almost nothing, since merging a standing release PR takes seconds and is the one step where a bad change becomes irreversible.

## 13. Should a release wait for a cancelled check, or fail?

`verify-release-checks` treats a **cancelled** required check as a failure.

That is what silently skipped the iOS build for client 0.17.0 on 2026-07-31: merges in quick succession cancelled the in-flight iOS check, the release gate read the cancellation as failure, and `ios-testflight` was skipped while the tag, the GitHub release and the changelog all looked perfectly correct.

#249 fixed the cause - the four release-gating workflows no longer cancel each other on main - so this path should now be unreachable.
**Confirmed on client 0.18.0 (2026-08-01):** `ios-testflight`, `android-client`, `linux-client` and `copr` all ran and all succeeded, on a release cut minutes after several merges in quick succession, which is the exact shape that broke 0.17.0.
Worth saying how that was confirmed, since the failure mode is invisible: the release run's individual job conclusions were read, rather than the release being trusted because it was green.
A release with a skipped store build is green.
The behaviour on the day it *is* reachable again is still the same, though, and the symptom is again a store build that quietly never arrives rather than a red release anybody would notice.

*Question:* should it re-run the cancelled check and keep waiting, or keep failing fast?

Waiting means a release can block for as long as the check takes (the iOS one is about 13 minutes) and could in principle loop.
Failing fast means the release is wrong in the one way nobody sees.
Recorded rather than chosen, because it is a trade about how long you are willing for a release to hang rather than a correctness question.
