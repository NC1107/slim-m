# Screen inventory: moderation, safety, and blocking states

Part of [screen-inventory.md](screen-inventory.md).
These are the states reachable only from a combination of conditions the task specifically calls out.
Neither harness fixture sets a block, a timeout, or a permission-mixed report queue anywhere, so coverage below is almost uniformly none; this file exists to make the combinations explicit rather than to report on captures that exist.

## Member popover permission-combination matrix

- **member-popover-self** — only "Profile settings"; no Message, no moderation section, no report/block section. Reach: open your own row.
- **member-popover-plain** — an ordinary member with no moderation rights: Message/Mention + Report/Block only. This is plausibly what the overlay harness's fixed `member-profile-popover` instance renders, though its exact permission fixture was not confirmed by reading alone.
- **member-popover-blocked** — "Unblock" replaces "Block." Reach: the viewed member is on your own block list.
- **member-popover-blockable** — default "Block," danger-toned.
- **member-popover-timeout-badge-liftable** — a currently-timed-out member's badge with a "Lift" button. Reach: `timedOutUntil != null` and you hold `KICK_MEMBERS` and aren't targeting yourself.
- **member-popover-timeout-badge-readonly** — same badge, no Lift button. Reach: `timedOutUntil != null`, you lack `KICK_MEMBERS`.
- **member-popover-timeout-chips** — 5m/1h/24h/7d quick-timeout chips. Reach: you hold `KICK_MEMBERS`, target has no active timeout, not self.
- **member-popover-timeout-error** — inline `AppErrorState`, popover stays open. This is the one moderation action here that renders its failure in-place rather than as a `SnackBar`, since the popover isn't dismissed before the request runs.
- **member-popover-eject** — "Eject from call..." Reach: `inCallTogether` (both of you in the same voice channel right now) and you hold `KICK_MEMBERS`. Confirmation dialog; popover closes before the request, so failure is `SnackBar`-only.
- **member-popover-remove** — "Remove from Space" (ban). Reach: `BAN_MEMBERS`, not self. Same close-then-request shape as eject.
- **member-popover-roles** — opens the role-assign sheet as a second surface. Reach: `MANAGE_ROLES`.
- **member-popover-call-audio-only** — `inCallTogether` true but no `KICK_MEMBERS`: mute-for-me and the volume slider (where `supportsParticipantVolume`) show, no Eject row.
- **member-popover-admin-containment-gap** — a real finding worth capturing deliberately: the client computes `canTimeOut`/`canRemove`/`canManageRoles` from **only the caller's own bits**, with no client-side check that the caller's granted permissions actually contain the target's (the server enforces containment, the client does not preflight it). A `KICK_MEMBERS`-holding moderator viewing an administrator whose permissions exceed their own sees the Timeout/Remove rows present, and only discovers the refusal after tapping, landing in the inline-error or SnackBar-failure states above rather than the rows being absent — arguably a violation of this codebase's own "absent, not disabled" convention, and worth confirming against a real fixture.

## Blocked DM / one-way vs. two-way asymmetry

- **dm-blocked-by-me** — `BlockedDmNotice` replaces the composer: warn-tone callout naming who's blocked, an "Unblock" button, inline `AppErrorState` on failure. Reach: your own `blocksProvider` contains the DM partner.
- **dm-blocked-by-them-invisible** — **no client-side signal exists for this case at all.** The composer renders normally and stays fully interactive, since the block check reads only your own list; the server still denies send/react/attach both directions the moment either side blocks. A send attempt from here fails server-side and renders as an ordinary failed-message row with retry/discard, with nothing explaining it's a block rather than any other send failure. Worth capturing precisely because it is a genuine gap, not merely an undertested state.
- **dm-blocked-mutual** — renders identically to `dm-blocked-by-me` for the party whose own list contains the block; never a distinct third rendering.
- **dm-call-evicted-on-block** — blocking mid-call evicts the blocked party (never the blocker) from a shared DM call. The evicted party's screen is indistinguishable from a moderator's kick or a stale-heartbeat sweep eviction (same generic `VoiceDisconnect` copy). See the voice doc's disconnect-reason list.

## Report flow, beyond the compose sheet already listed in the overlays doc

- **report-submitted-toast** — a transient `SnackBar` only; there is no persistent "your reports" record anywhere in the client. Legitimate per the SnackBar exemption (the popover/menu that triggered it is already closed).
- **report-queue-scope-excluded** — a report about a channel the moderator cannot moderate never appears in the queue at all (server-side pre-filter); confirmed there is no client-side "you can't act on this" placeholder card. This satisfies the stated design goal (excluded, not shown-then-refused) but is worth a deliberate capture of a permission-mixed queue to actually prove, since the harness's queue is always empty.
- **report-card-message-full-actions** — moderator holds `MANAGE_MESSAGES`, `KICK_MEMBERS`, `BAN_MEMBERS`, and the channel is reachable: Jump/Delete/Remove/timeout-chips all present together.
- **report-card-no-quick-actions** — moderator holds none of the three action bits: the whole quick-actions block collapses to nothing.
- **report-card-jump-unreachable** — Jump renders **disabled**, not absent, when the local store doesn't have the channel (deleted, or one the viewer was never a member of). A deliberate exception to the usual absent-not-disabled rule, since the client can't tell "deleted" from "not yet paged in" without trying.
- **report-card-self-target** — `canTimeOut`/`canRemove` forced false regardless of bits when the reported subject is the viewing moderator themself.
- **report-card-author-gone** — "Author no longer on this Space"; Timeout/Remove vanish since there's no target id.
- **report-card-reporter-gone**, **-reporter-resolving**, **-reporter-anonymous** — three distinct renderings of the reporter line depending on lookup timing and outcome (a null id, a resolving id, and a resolved-but-null profile all read differently: "a deleted account," "someone," "a deleted account" — the first and third share copy but reach it through different paths).
- **report-card-no-snapshot** — the reported-content block is entirely absent when `snapshot == null` (message deleted before capture, or a user-kind report, which never has one).
- **report-card-busy**, **-auto-resolved-on-success** — see the settings doc.

## Removed members

- **removed-members-populated**, **-empty**, **-restore-busy**, **-restore-error**, **-no-reason** — see the settings doc for the full list; repeated here only for the reachability note: a removed account is durably signed out (`space_removals`) and cannot sign back in with the same account, though nothing stops a fresh registration on an open Space. There is no dedicated client screen for the removed party's own experience; it is the generic sign-in failure path.

## Timeout's effect on the timed-out member's own client

- **timeout-composer-not-locally-gated** — no code found that disables your own composer client-side while you are timed out; a send attempt would fail server-side and render as an ordinary failed-message row, the same shape as the invisible-blocked-DM gap above. Flagged as worth verifying directly against `composer.dart` rather than confirmed absent — this file was not read in full during this pass.

## Canvas activity log actor disclosure

- **canvas-log-actor-disclosed** — catch-up-fed entries carry whatever `GET /canvas/ops` already decided to disclose (real actor only if the caller holds `MANAGE_CANVAS`, or unconditionally for a `place`, which is never a moderation act).
- **canvas-log-actor-withheld-live** — live socket frames for `remove`/`clear`/`restore`/`move` never carry an actor at all, for any viewer regardless of permission, rendered passively ("An object was removed.") with no invented name. This is the documented asymmetry: the same event, seen later via catch-up by a manager, would have named the actor.
- **canvas-log-actor-blocked-hidden** — an entry whose disclosed actor is on your block list is dropped before it reaches the list or the announcer; a withheld (null) actor is never filtered, since there's nothing to match.

## Voice roster / presence — appear-offline

- **voice-roster-preview-hides-hidden** — the pre-join roster preview structurally drops any participant with hidden presence, for every viewer but themselves, enforced server-side.
- **voice-live-call-discloses-hidden** — once actually joined, LiveKit itself must tell participants about each other, so the same hidden person's identity **is** visible in the live in-call roster with no filtering. A genuine, documented, and permanent asymmetry between the pre-join preview and the joined-call roster for the identical person — worth a deliberate side-by-side capture since it can't be demonstrated by either state alone.
