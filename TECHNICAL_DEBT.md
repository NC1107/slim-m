<!-- SPDX-License-Identifier: Apache-2.0 -->
# Technical debt

From the 2026-07-29 multi-agent audit against `main`.
Every item below was confirmed by reading the code path or running a probe against the real router, not by reasoning from a comment.
Struck through when fixed, with the commit that closed it.

## Summary

16 confirmed: 2 high, 5 medium, 5 low, 4 test-quality. All the highs and mediums are being fixed in this pass; the lows and test-quality items are fixed where cheap and recorded where not.

## High

- **H1. A report about a DM, or about a message in a since-deleted channel, is accepted then permanently invisible and unresolvable.**
  `list` and `resolve` (`http/reports.rs`) re-check `MANAGE_MESSAGES` in the report's own channel; a `dm`-kind channel grants that to nobody, and a soft-deleted channel resolves to `NONE`, so intake returns 200 while no moderator can ever see or close it.
  Probe: file from a DM -> 200; admin `GET /reports` -> `[]`; `open_report_count` -> 1; `PATCH /reports/{id}` -> 404.
  Fix: a report with no viewable channel (DM, deleted, or `user`-subject) is a deployment-level report, gated on `MANAGE_MESSAGES` at base scope rather than in a channel that cannot grant it.

- **H2. `POST /reports` is unthrottled and never checks that a `user` subject exists, so the queue floods without bound while clearing it is rate-limited.**
  `file_report` (`http/safety.rs`) calls no `enforce`; the dedup index is keyed on `subject_id`, so a fresh random UUID per request is a fresh open report per request, each with 2000 chars of attacker text.
  Probe: 200 of 200 accepted, 0 refusals; cleanup (`PATCH`, Write class) stopped at 30 with 429.
  Fix: charge `Class::Write` on intake, and 404 a `user` subject that does not exist.

## Medium

- **M1. The attachment fetch is a 403-vs-404 existence oracle over content-addressed ids.** `GET /attachments/{sha256}` answers 404 for bytes nothing has attached and 403 for bytes attached in a channel the caller cannot see, so anyone holding a candidate file learns whether it was shared privately here. Fix: 404 when the caller can view none of the referencing channels, collapsing the two the way search and the channel API already do.
- **M2. Typing events reveal appear-offline users.** `handle_typing` publishes `TypingStarted` with the user id to every VIEW_CHANNEL connection with no visibility check, bypassing `status_for`. Fix: drop the frame when the typist resolves to Offline for that viewer, at the existing per-viewer choke point.
- **M3. The command palette opens the settings modals with `context.go`, not `push`,** so closing one strands the user on `NoChannelSelected` with the channel lost, and it cold-opens as an opaque app-background panel instead of a modal floating over the app. Fix: `push` at both call sites.
- **M4. `SyncController`'s detached catch-up continuation swallows its errors and stops silently while `state` stays `live`.** A REST failure mid-backlog with the socket still up (a 429 from the server's own limiter, a transient 5xx) leaves a permanent gap the UI reports as live. Fix: route a failure to offline plus a scheduled retry.
- **M5. `PinsController.refresh` assigns `state` after an await with no `mounted` guard on an `autoDispose` family,** so switching channels mid-fetch throws an unhandled `StateError`. Fix: a `mounted` guard, matching `channel_search_controller`.

## Low

- **L1. The canvas viewport reads its object page before the sequence cursor,** so a concurrent placement is skipped forever. Latent: no write route is mounted yet, but the ordering would survive silently into Phase 6. Fix: read the cursor first.
- **L2. Re-uploading identical bytes keeps the original `created_at` (`ON CONFLICT DO NOTHING`),** so the orphan sweep can delete a just-rewritten file inside the compose window and the send then 400s. Fix: `DO UPDATE SET created_at`.
- **L3. Retrying a send whose message was deleted in between returns 500,** because the idempotency probe filters `deleted_at IS NULL` and the re-insert hits the unique id. Same in polls. Fix: probe without the filter, or map the unique violation to a conflict.
- **L4. `POST /invites/{code}/redeem` and `POST /channels` charge no rate limit,** and redeem takes the SQLite write lock on every miss. Fix: `enforce(Class::Write)` on both.
- **L5. Blocking a never-existed user returns 500,** because `INSERT OR IGNORE` does not cover a foreign-key violation. Fix: existence check, or catch the FK violation as not-found.

## Test quality

- **T1. `reduce_motion_test.dart:156` asserts inside a loop over a `widgetList` it never asserts is non-empty,** so it passes on an empty match. Fix: assert the list is non-empty first.
- **T2. `test_sounds.py`'s levelness test measures with the same `loudness` used to set the level,** so it is near-circular; the independent `gated_loudness` written for exactly this has zero call sites. Fix: check levelness with the independent meter. (Author's own test.)
- **T3. The desaturated-presence golden never runs** (`SLIMM_GOLDENS` is set nowhere), so only the pixel-difference test in the same file actually guards the claim. Low: the important assertion does run.
- **T4. `capabilities.rs` does not prove `/version` reflects a router *without* the safety routes,** so hardcoding the wiring survives the suite. Fix: assert an empty capability list flows through `/version`.

## Progress

All fixed 2026-07-29 in the `fix/audit-security` branch, except T3 (left as-is,
the pixel-difference test in the same file is what actually guards that claim).

- [x] H1  - [x] H2  - [x] M1  - [x] M2  - [x] M3  - [x] M4  - [x] M5
- [x] L1  - [x] L2  - [x] L3  - [x] L4  - [x] L5
- [x] T1  - [x] T2  - [~] T3 (superseded by the pixel test)  - [x] T4

Each behavioural fix carries a regression test, and each was mutation-tested by
reverting the fix and confirming the test fails, except M4 and M5, which are
async-lifecycle guards matching an established sibling pattern and are fixed by
inspection rather than a flaky timing test.
