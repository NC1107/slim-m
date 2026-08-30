<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->
# Brief for the design agents (2026-07-29)

Paste this into the Claude Design project. It says what shipped, what the
implementation learned that the specs could not have known, and where a
design decision would unblock work that is currently guessing.

---

## Where the build actually is

Three of your specs are implemented and released in client 0.11.0, plus the
prod review's token-compliance list. Concretely, in the Flutter client:

**From the prod review.** `buildTheme` now carries the system rather than
leaving raw Material widgets on M3 defaults: control-radius button shapes
(6, not stadium), the hairline boxed input, an AppBar title from the scale,
and a `TextTheme` mapped from `AppText` whose heaviest weight is 600. Icons
moved to the 1.5-stroke Lucide cut. The wordmark renders in mono, medium,
+0.04em. Timestamps and date dividers are mono with tabular figures. Danger
is outlined everywhere, never filled. Channel-row kebabs reveal on hover or
focus.

Five of that review's ten items were **measurement artifacts**, worth knowing
so the next review does not re-file them: the accent has not drifted (tokens
are exactly `#1B6F91` / `#58B4D8`; the review sampled anti-aliased pixels),
the dark base is exactly `#17191C`, nothing renders at 700 (the ramp stops at
600 and no bolder face is loadable), the reaction "tofu" is a font gap in our
screenshot harness rather than the product, and the fingerprint confirmation
step exists and is wired into onboarding - cold renders just never walk the
connect flow.

**Motion & Feedback.** All eleven patterns, each routed through a
reduce-motion helper so every one collapses to an instant state change.
Selection marker grows from centre on its own clock beside the 100ms hover
fill; reaction chips and unread dots pop once and then sit still; the member
pane slides from its own edge; compact navigation is the drill-down with 30%
parallax; modals take 280 in and 180 out; the connection banner animates its
height so it pushes rather than covers; long-press shows hold progress;
theme switching is 0ms.

**Error States.** The grammar is in force: amber is transient, red is
outlined and attached to what failed, failures persist rather than toasting,
and nothing the user wrote is discarded. Message lifecycle marks sent /
sending / failed, and a failed message keeps full opacity with Retry / Edit /
Discard - Edit returns the text to the composer. Sign-in errors land on the
field that failed. There is now an `AppErrorState` component and an
`AppAsyncView` that gives every fetched surface one loading / empty / error
treatment.

## Two places the implementation had to depart from a spec

**Invite errors (Error States 05).** Not implemented, and it should stay that
way unless the security model changes. The server answers *expired*, *spent*,
*revoked* and *never-issued* identically so invite codes cannot be mined by
probing; naming the reason client-side would undo that from the other end.
The safe half is a purely local format hint ("codes look like XXXX-XXXX")
that contacts no server, and that is worth designing.

**Queued-message count (Error States 02).** Built and then reverted: reading
it needs a live database stream in the rail footer, which prevented every
test rendering the rail from ever settling. The banner keeps its amber tone
and the composer is never blocked. A design that expresses "some are waiting"
without a live count would ship immediately - or confirm the count is worth a
polled read.

## What we cannot design our way past without you

These are the places implementation is currently guessing, ordered by how
much a decision unblocks.

**1. A screen at rest is mostly empty, and we do not know what belongs
there.** The channel pane is bottom-anchored, so a young channel shows a
large blank band; the in-call screen for two people uses about 15% of its
height. We added a start-of-channel header and call tiles as stopgaps. The
real question is what a *quiet* slim-m looks like - a small friend group is
quiet most of the time, and every screenshot you have reviewed is of an
almost-empty deployment. Design for the empty and near-empty case as the
primary state rather than the degenerate one.

**2. Member profile popover.** Members are click-dead in the member pane.
This is the natural home for per-user volume, block, DM, role display and
timeout, all of which we have either built server-side or accepted for v1
and cannot place. One popover design unblocks four features.

**3. Voice, past the roster.** The call surface currently renders avatar
tiles and a screen share. There is no design for: per-participant volume
(accepted for v1), camera video (no capture path yet, but the tile layout
should anticipate it), the connection-degradation states your own Error
States spec describes (video paused to protect audio, a peer mid-reconnect),
or what a call looks like at 8 people versus 2. The last one matters most:
the tile layout we shipped is a guess about a size we have never seen.

**4. The self-hosting trust surface.** The fingerprint step exists but its
design is ours, not yours: an unfamiliar-server warning, the
fingerprint-changed warning, and the "can't reach this Space" screen your
Error States spec sketches. This is the product's differentiator and the
place a bad design does real harm, since it is where someone decides whether
to trust a server their friend runs.

**5. Density, for real use.** Every render you have seen has three messages
in it. We tightened message spacing by feel. What we lack is a design for a
busy channel: a long run from one person, a conversation with attachments and
reactions interleaved, a day boundary mid-scroll, mentions in a wall of text.
If you produce one screen, make it a full one.

**6. A found gap: no compact-width design exists for the admin screens.**
Roles, invites, reports, channel permissions and emoji were designed as
desktop lists; we render them full-screen on a phone with the same rows. They
work, but nobody designed them for a thumb.

## How to hand work back

The three specs so far have been directly implementable, and the reason is
worth repeating: each named its durations, its tokens, and its Flutter
equivalent inline. Keep doing that. The pattern that works is a live demo
plus a mono line saying `180ms · ease-out · transform, opacity` and
`Flutter: AnimatedScale + AnimatedContainer`.

Two additions that would help:

- **Say which state is primary.** Several screens have a designed full state
  and an undesigned empty one, and the empty one is what ships to a new
  deployment.
- **Name what you are not specifying.** The Error States spec's four rules at
  the top were more useful than any single card, because they let us decide
  the twenty cases the spec did not draw. More rules, fewer cards, where you
  have to choose.

## Reference

- Screenshots: 60 renders of all 12 routed screens (phone and desktop, both
  themes) plus 13 captures from a live two-user session, uploaded as
  `slim-m-screens-2026-07-29`. Note the README's list of harness artifacts.
- The component library in this project is real and in use; the Flutter side
  mirrors it component for component.
- Implementation notes, including every finding and every deliberate
  non-action, are in `docs/research/nine-specialist-audit-2026-07-29.md`.
