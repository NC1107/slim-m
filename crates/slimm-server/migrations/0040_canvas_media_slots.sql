-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Where a call participant's camera or screen-share tile sits on a channel's
-- canvas, shared by every viewer - decision 0010's reversal of its own
-- original call, which kept this per-viewer and ephemeral in client memory
-- alone. One row per (channel, participant, kind): a slot is a place saying
-- "this person's video goes here", empty when nobody is sharing that kind
-- and filled when they are, which is why it is worth remembering even while
-- unfilled rather than only while a call holds it.
--
-- Deliberately not a canvas_objects row and not part of the canvas_ops op
-- stream. A slot has no author in the sense that table means it - "whose
-- camera" names the participant a tile represents, not who arranged it, and
-- anyone with USE_CANVAS may rearrange anyone's slot the way any Figma
-- editor may drag any sticky note, so the own-object-versus-MANAGE_CANVAS
-- split canvas_ops_apply.rs enforces for authored content does not apply
-- here. A slot also mutates in place rather than appending: canvas_ops'
-- move and reorder kinds are never swept, so logging one op per drag frame
-- would grow that table forever for state nobody needs a history of, only a
-- current value.
--
-- The primary key is what answers the concurrency question directly rather
-- than needing an app-level lock: two viewers racing to touch the same
-- tile for the first time cannot create two rows, since SQLite's single
-- writer serializes the pair of INSERT ... ON CONFLICT DO UPDATE calls and
-- the second simply overwrites the first.
--
-- locked and sent_to_back are shared here too, not only position and size -
-- the owner's own instruction was "position, size and depth are shared", and
-- lock is treated the same way: it protects an arrangement everyone relies
-- on, the same shared-lock behaviour Figma and FigJam themselves use, rather
-- than a personal "how my own pointer behaves" setting that would let
-- someone else drag a tile its own arranger just locked.
--
-- Hidden is deliberately absent: hiding a tile stays a personal view choice,
-- kept client-side in CanvasPresenceTileOverrides exactly as blocking
-- already is, never written here.
CREATE TABLE canvas_media_slots (
    channel_id   BLOB NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    user_id      BLOB NOT NULL REFERENCES users(id),
    kind         TEXT NOT NULL,
    x            REAL NOT NULL,
    y            REAL NOT NULL,
    w            REAL NOT NULL,
    h            REAL NOT NULL,
    locked       INTEGER NOT NULL DEFAULT 0,
    sent_to_back INTEGER NOT NULL DEFAULT 0,
    updated_at   INTEGER NOT NULL,
    PRIMARY KEY (channel_id, user_id, kind),
    CONSTRAINT canvas_media_slot_kind CHECK (kind IN ('camera', 'screen')),
    CONSTRAINT canvas_media_slot_locked_bool CHECK (locked IN (0, 1)),
    CONSTRAINT canvas_media_slot_sent_to_back_bool CHECK (sent_to_back IN (0, 1))
) STRICT;

-- Account deletion removes a departed member's own slots outright (a slot
-- with nobody left to represent is not content worth anonymizing the way a
-- message or a canvas_objects row is), which needs this to filter by.
CREATE INDEX canvas_media_slots_user ON canvas_media_slots(user_id);
