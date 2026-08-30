-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- A private, per-author note about another account ("prior warning",
-- "prefers they/them"). Keyed like user_blocks (0005_safety.sql): one row
-- per (author, subject) pair, WITHOUT ROWID. A note is the author's own
-- data - never shown to the subject or to anyone else, and there is no
-- moderation surface for it - so `Store::delete_account` purges every row an
-- author leaves behind, the same way it purges reactions and read state.
--
-- No reverse index: unlike user_blocks, nothing ever asks "who has notes
-- about this subject" - there is no fan-out, no push, no enforcement path
-- that reads this table from the subject's side, only ever a lookup keyed by
-- the author asking about one subject at a time.
CREATE TABLE user_notes (
    author_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject_id BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    PRIMARY KEY (author_id, subject_id)
) STRICT, WITHOUT ROWID;
