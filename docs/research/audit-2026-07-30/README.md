<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->
# The full-stack audit (2026-07-30)

Thirty-three specialist reviews over the whole stack, every one put through a
second reviewer whose job was to knock the findings down.
528 findings survived that; 98 did not.

This was the written-down state of the project on the day it was written.
Much of it has since been closed; see the status below before working from any
report here, and correct that section rather than leaving it to rot, because
this document's whole purpose is stopping re-discovery.

## Status, 2026-07-30

Each report ends with the three its author would do first. All fifteen of those
are closed except where noted, and the security report's full set is closed.

| Report | The three to do first | State |
| --- | --- | --- |
| Security | all sixteen findings, not three | closed: #145, #147-#153, #155 |
| Server code | role-removal containment; publish the missing events then cache permissions; the rate-limit extractor | closed: #149, #161 then #165, #145 |
| Screens | report card identity; pin `primary` and `ListTileTheme`; the snapshot fixture | closed: #157, #162, #166 |
| Client code | the message path and item keys; dismiss-then-act; the failure-reporting migration | closed: #154, #159, #167 (with #160) |
| Process | gate the tag-push publish path; the `SlimmApi` reachability gate; the stale documentation | closed: #158, #169, #164 |

Also closed from the wider set: the WebSocket frame set is documented and gated
(#163), and `Hub`'s duplicated constructor and the healthcheck's `Config`
bypass (#171).

This table was last rebuilt in #173.
Closed since then, evidence cited by PR rather than carried over: **the
`messages_fts` rowid rebuild** (#183, migration
`0024_messages_rowid_alias.sql`, moved out of "deliberately still open"
below); the screens report's member-roster truncation at 50 (#181) and
missing channel history pagination (#197); and three admin-screen defects the
screens report named outside its top three - the invites screen's uncopiable
code and unshown role grant, and the emoji upload's missing preview and
unenforced clear (#175), plus roles offering "Assign" on `@everyone` (#190).
`schema/README.md`'s stale codegen and CI-gate claims and two stale line
counts in `scripts/file-budget-allow.txt`, both named in the process report,
were corrected directly in this same pass rather than by an earlier PR.

**Deliberately still open**, with the reason rather than by omission:

- **Six unreachable `SlimmApi` methods**, down from seven: `canvasViewport`
  gained a caller in #198, the canvas write slice.
  The gate that stops a seventh is in (#169); the six remaining are
  allowlisted with dated reasons, and two of them are the whole of the
  account-recovery owner decision, which has no UI at either end.

Several findings turned out to be **already fixed when checked**: the
server-identity tick reads the pinned fingerprint and has a `mismatch` state,
`listUsers` has callers, and both Phase 4 items the process report lists (the
voice join roster and `MediaCapabilities.probeAll`) were closed on 2026-07-28.
That is the same drift this audit's own process report is about, and it is why
this section exists.

## The five reports

| Report | What it covers |
| --- | --- |
| [Screens and experience](screens.md) | All eleven routed screens, rated, from the real renders at four widths in both themes |
| [Client code](client-code.md) | Every Dart package: cleanup, componentisation, duplication, render performance |
| [Server code](server-code.md) | Every route and store module: correctness, duplication, query cost, schema |
| [Security](security.md) | Server authorization route by route, client secrets and storage, input validation and denial of service |
| [CI, tests and documentation](process.md) | Workflows and packaging, whether the tests can fail, and whether the docs are still true |
| [What did not survive](rejected.md) | The 98 rejected findings and why, so nobody re-files them |

## Why the rejected list is part of the deliverable

The previous audit had roughly a quarter of its findings turn out to be
measurement artifacts, and two of those were quoted forward into later
documents as though real.
So each scope's findings went to a second agent told to refute them, to default
to rejecting anything it could not confirm from the code itself, and to
downgrade severities freely.
Every reviewer also got the known false-positive list up front - the accent has
not drifted, nothing renders at weight 700, the blank avatars in older renders
were a harness bug, the invite expired-versus-invalid ambiguity is deliberate -
so none of that ground is re-litigated.

## What each area said to do first


### Screens and experience

**1. Give the report card an identity, and the queue a way to act.**
`reports_screen.dart` is the only screen in this audit that cannot perform its stated purpose: the moderator is asked for an irreversible close on a subject the screen does not name, and for a user report there is no identifying information on screen at all.
Everything it needs is already on the model and already served, and the batch profile fetch exists.
It is also the one finding here that is a safety-model problem rather than a polish problem.

**2. Pin `primary` and add a `ListTileTheme` in `buildTheme`.**
Two additions in one file correct the brand accent on every raw Material button in the app and the row text and icon colour on all fifteen raw `ListTile` sites, which between them account for a large share of the "off-palette" findings on every screen.
`error` was pinned for exactly this reason one audit round ago; this is finishing that change rather than starting a new one.
The same file is where the input label and hint styles belong, and the dead modal border is one line away in `modal_page.dart`.

**3. Point the snapshot fixture at real data, at the widths where layout changes, through the shipped app wrapper.**
The three highest-severity screen defects - the clipped role name, the mislabelled spent invite, the unclamped report body - all live in states no render and no overflow assertion has ever produced, and one finding in this pass was generated purely by the harness diverging from `main.dart`.
Until the gate renders populated rows at the breakpoints that matter, under the density and presentation the product actually ships, every fix above is unprotected and the next equivalent defect will survive the same way.

Runners-up, close behind: the spent-invite label (a one-condition correctness fix on a screen an operator uses to debug why a friend cannot join), and the missing image preview on the emoji upload.


### Security

1. **Fix the unauthenticated availability pair (findings 1 and 2) together.**
Both are reachable by anyone who can open a socket, both take a handful of requests, and one of them takes login offline for the whole deployment on the exact topology the owner runs.
They also share a fix surface (the proxy config plus one router layer), and the socket path already proves the team holds these bounds as necessary, so there is no design question to settle first.

2. **Make blocking do something in shared channels, or change the copy (finding 3).**
It is the only finding where the product tells a user they are protected and they are not, and it is one of exactly two safety tools this product ships.
The capability handshake advertises it and the roadmap records the criterion as met, so no existing gate will ever catch this.
Filtering at read time is contained client work; the alternative, honest copy, is one afternoon.

3. **Make the attachment reference an authorization decision (finding 10).**
It re-opens, from a route nobody audited, the precise existence oracle that `GET /attachments/{id}` has a written refusal to build, and it hands the caller the bytes rather than merely the answer.
It also quietly breaks two things the codebase believes it guarantees: revocation of view access, and an author's delete unsharing their file.
It needs a schema decision (an uploader column) so it is the one of the three that will not get smaller by waiting.

Immediately behind those: the rate-limit charge should stop being opt-in per handler rather than being fixed eight times.
That single layer closes seven findings at once and is the only thing that stops this same defect being found by a third audit.


### Server code

**1. Containment on role removal (`http/roles.rs`).**
It is the only high-severity security finding, the escalation is reachable by a single request from a `MANAGE_ROLES` holder, the guard already exists in two other modules to copy from, and the fix is small.
Everything else here is either latent, needs a specific failure to fire, or is a cost rather than a hole.

**2. Publish the missing role, overwrite and channel events, then cache per-connection permissions (`http/ws.rs`, `http/roles.rs`, `http/overwrites.rs`, `http/channels.rs`).**
The first half is a live staleness bug on its own - a revoked channel view never reaches a client - and it is also the only thing that makes the cache invalidatable, so the ordering matters.
This is the recorded item that has been open longest and the crate's largest recurring cost.

**3. Make the rate-limit charge an extractor and close the six uncharged routes (`http/extract.rs`).**
Four specialists found it independently, the phase-3 audit already found the identical omission once, and `ratelimit.rs`'s own class doc names a route it does not cover - so the current mechanism has now demonstrably failed twice in the same way.
Moving the charge into the signature also removes `parts: Parts` and its clone from 47 handlers and turns "no limit" into a visible, reviewable choice.

Worth queueing right behind those: the `messages_fts` rowid licence, because it is far cheaper to fix before the Phase 9 `VACUUM INTO` work is written than after, and its failure mode is silent wrong search results.


### Client code

**1. The message path: `message_store.dart`'s two ordering bugs plus item keys on the transcript.**
`watchChannel`'s ascending limit, the pending row's `seq` of 0, and the missing `ValueKey(message.id)` are three small edits in two files, and together they are the only findings in this area with no in-app recovery.
The ordering one silently disables the transcript and the read marker for any channel that reaches 200 messages, which is one evening of use, and there is no test in `packages/data` that would notice.
The keys one loses text the user has typed, which the project treats elsewhere as a line it does not cross.

**2. `member_profile.dart`'s dismiss-then-act helper.**
Removing a member and reporting a member are the two moderation paths with a single call site each, both currently guaranteed to throw `StateError` past every catch, and both green in CI because every test passes `onDone: () {}`.
The fix is to resolve what the action needs before the surface is dismissed, and the test that would have caught it is one case driving `showMemberProfile` through a real route.
This is a safety-model gap, not a polish item.

**3. The failure-reporting migration onto `runGuarded` and `AppErrorState`.**
It is the largest single componentisation win in the client (24 write sites, 26 SnackBars across 16 files, five reinventions of the inline error), it is what the cleanup question was asking for, and it closes a defect the repository already has a committed test against: `client_transport.dart` wraps every network fault in a string containing the method, path and Dart exception, and 24 sites render it.
Do `voice_controller.dart:196` first inside that work, because its string reaches a full-screen surface on the flagship feature.
Two prerequisites are cheap and belong in the same pass: add the missing `ForbiddenException` clause so the 401 and 403 wording stops being inverted, and put an `analysis_options.yaml` at `client/` so the six unlinted packages start being analysed at all.

One scheduling note rather than a fourth item: `voice_screen.dart` sits at exactly 500 lines, so the next net addition to voice fails the hygiene workflow for a reason unrelated to the change making it.
Its seam is already named (the pre-call screen, lines 83-293), and splitting it before it is next touched is cheaper than discovering it under CI pressure.


### CI, tests and documentation

**1. Gate the tag-push publish path (release.yml:51).**
It is the only finding here where a single command with no failing signal ships an untested binary and an untested signed image to a production deployment that auto-updates.
Everything else in this section costs time; this one costs a release.

**2. Add the app-side reachability gate for `SlimmApi` (client/packages/api).**
Seven unreachable methods is the same defect this project has already shipped three times, and two of them are the whole of the account-recovery owner decision.
It is also the only finding whose fix creates a permanent gate rather than a one-off correction, and the pattern to copy already exists in `tests/response_contract`'s `UNCOVERED`.

**3. Correct schema/README.md, STRATEGY.md's codegen and scanner claims, and CLAUDE.md's four stale lists.**
These are cheap, and they are the findings that multiply.
The nine-specialist report exists specifically to stop re-discovery and half its open list is closed; CLAUDE.md tells contributors that a permission gate lives in a file that was deleted and that four built features are not built; and three documents promise machine guarantees that would stop a reader from checking by hand.
Every hour spent on a problem that no longer exists is charged to this entry.
