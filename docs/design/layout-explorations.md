# Layout explorations (parked for later)

Status: parked.
Date: 2026-07-23.
Decision: keep the familiar sidebar layout (Discord/Slack-style, but calmer) for v1.
These alternative organizing concepts are recorded for a possible later revisit, not scheduled.


> **Revisited 2026-07-26** (see `../decisions/0004-visual-identity-review.md`).
> The worry that these were parked too early was based on a wrong framing.
> **Focus is not an alternative shell** - it is the compact breakpoint plus a
> command palette, and both already ship. **Deck is not a layout** - it is a
> landing pane that can live where the channel list points when nothing is
> selected, addable later with no rewrite. Only **Spaces** was a genuine fork,
> and declining it for heads-down text was the right call. What was parked is
> two additive features, not two roads not taken, so nothing here needs
> reopening.


## Why there is room to diverge

Two decisions give slim-m freedom to organize the UI differently from Discord if it ever wants to.

One backend deployment is one community (owner decision), so there is no need for Discord's column of server icons, which exists only because one account spans hundreds of servers.
That frees the entire left edge.

The Voice Canvas is already a spatial, arrange-objects-in-space feature.
Two of the concepts below reuse that spatial thinking for navigation itself, so the signature feature and the everyday shell would feel like one idea rather than two.

## Concept 01: Spaces (spatial, canvas-native)

The community is a zoomable board.
Channels and voice lounges are rooms arranged in space, with people shown as dots inside them, so you glance at the whole community at once and zoom into a room to focus.
The Voice Canvas is not a separate mode; it is the same plane you already navigate.

- Voice lounge: a room you zoom into, camera bubbles and canvas already in place.
- DMs: personal rooms docked at the edge or floated onto your own private board.
- Strengths: nothing on the market feels like this; ambient voice presence; shell and canvas become one idea.
- Risks: spatial navigation is slower than a list for heads-down text chat; hardest to make fast and legible on a phone; real accessibility and muscle-memory cost.

## Concept 02: Focus (single-column, command-driven)

Strip the chrome to one calm reading column.
No always-on channel list or member list; you summon anything with a command bar (one keystroke on desktop, a pull-down on mobile).
Channels and DMs are one unified list of conversations.
Voice rides along as a slim dock that expands into a full lounge, so a call never takes over the screen.

- Voice lounge: expand the dock to a roster with camera bubbles; canvas opens as an overlay on demand.
- DMs: first-class, in the same conversation list as channels.
- Strengths: calmest and most understated; best reading experience; collapses to a phone with zero rework; least chrome means lightest and longest-lived; unifying DMs and channels removes an artificial split.
- Risks: less at-a-glance awareness (summon rather than see); leans hard on a great command palette and search; density fans may find it sparse.

## Concept 03: Deck (ambient, live tiles)

The front door is a board of live tiles, one per channel and voice lounge, each showing current state.
A voice tile shows who is talking now with mini camera bubbles; a text tile shows the latest message and unread count; a DM tile shows the last line.
You glance at the deck to feel where the energy is, then tap into a room for a focused view.

- Voice lounge: tap a live voice tile to enter its focused room with bubbles and canvas.
- DMs: mixed into the deck as tiles, or filtered to a DM-only deck.
- Strengths: ambient presence is the front door, which fits a small friend group staying in contact; voice activity is visible without joining; warm and inviting.
- Risks: adds a home-then-room navigation layer over single-channel chatting; tiles get noisy as a community grows; needs live data on the home screen.

## Recommendation if revisited

Combine 02 and 03: open on a Deck home (who is around), drop into a single-column Focus view to read and type, with no server rail, DMs and channels unified, and voice in a dock that grows into a lounge.
Keep the fully spatial Spaces idea in reserve as an optional map view rather than betting the whole shell on it.

The interactive mockups that accompany these notes were shared as Claude artifacts (design proposal and layout explorations) during planning.
