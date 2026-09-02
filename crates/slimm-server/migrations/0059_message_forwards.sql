-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- What a forwarded message came from: which message, in which channel, by
-- whom, when, and what it said.
--
-- Forwarding used to be text. The client composed "Forwarded from <name>"
-- and a markdown quote into the sender's own content, so provenance was a
-- string nothing could reason about: no author to draw, no timestamp but the
-- forward's own, nowhere to jump back to, and no room for the forwarder to
-- say anything of their own without it running into the quote.
--
-- A side table rather than columns on `messages`, following the same call
-- 0030's threads made and for the same reason: `Message` is built by ten
-- different SELECTs across reads, search, pins, polls and read state, and a
-- field there is a field all ten have to carry. A forward is attached by
-- `message_enrich` in the batch it already runs for reactions, attachments
-- and thread summaries, so nothing else has to know.
--
-- Snapshot, not "resolve, don't copy" - the opposite of 0029's replies, and
-- for reasons that do not reach replies. A reply and its parent share a
-- channel and cascade away together; a forward crosses channels, so its
-- origin can be deleted, or live somewhere the reader cannot see, long after
-- the forward is written. Resolving live would blank a forward when its
-- original went, and would show nothing at all to a reader without access to
-- the source - where the forwarder plainly meant them to see something.
--
-- No REFERENCES on either origin id, which is the point rather than an
-- omission. A foreign key cascades: deleting a channel would delete every
-- forward of its messages living in other channels, destroying other
-- people's conversations as a side effect of tidying one's own. The origin
-- ids are soft - resolved while they still resolve, and a dead one costs the
-- jump, never the message.
--
-- origin_author_id stays an id rather than a snapshotted name, so a forward
-- anonymizes with everything else. Deleting an account is a tombstone
-- `UPDATE` setting `deleted_at` and `is_anonymized`, never a row removal,
-- and every display-name lookup already filters on that - so a deleted
-- author stops resolving here without this table knowing it exists. The
-- ON DELETE SET NULL mirrors `messages.author_id` for the same reason it
-- carries one there: nothing hard-deletes a user today, and a bare
-- reference would block it outright if anything ever did.
--
-- origin_content IS snapshotted, because it is the thing being forwarded and
-- has to outlive its original. An edit to the original after the fact does
-- not rewrite what was forwarded, which is also the honest reading: the
-- forward carries what was actually passed on.
CREATE TABLE message_forwards (
    message_id BLOB PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
    origin_message_id BLOB NOT NULL,
    origin_channel_id BLOB NOT NULL,
    origin_author_id BLOB REFERENCES users(id) ON DELETE SET NULL,
    origin_created_at INTEGER NOT NULL,
    origin_content TEXT NOT NULL
) STRICT;
