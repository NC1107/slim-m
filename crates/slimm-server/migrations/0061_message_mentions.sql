-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
-- Who a message mentions, resolved once at send (or edit) time rather than
-- re-derived from its text on every later read.
--
-- The resolver (`push::recipients::resolved_mentions`, reused rather than
-- reimplemented here) already turns `@name`, `@[Role]`, `@everyone` and
-- `@here` into a set of account ids at the moment a message is written; that
-- moment is also the only one at which "who could see this channel" and
-- "did the author hold MENTION_EVERYONE" are the values that were actually
-- true. Recomputing lazily on every list/sync read would answer with
-- whatever those happen to be *now* - a role renamed, a member who left and
-- rejoined, a permission since revoked - so this is a fact about the
-- message, stored the same way a reaction or an attachment is: a side table
-- keyed by the message, not a column on it every unrelated read of `messages`
-- would otherwise carry.
--
-- Row existence is the only signal; there is nothing else to store; a row's
-- presence means "this account was mentioned by this message", read back
-- per caller from `MessageDto.mentions_me` (`store::mentioned_messages_for`)
-- and per connection from `store::is_mentioned` on the live path.
--
-- (user_id, message_id) leads the primary key rather than the reverse,
-- because the hot read is "which of these messages mention me" (one caller,
-- many message ids), the same shape `reactions_for_messages` already reads
-- by leading on `message_id` for its own hot read (one message, many
-- reactors). The secondary index below serves the opposite direction: an
-- edit replaces a message's whole mention set, which deletes by `message_id`
-- alone.
CREATE TABLE message_mentions (
    user_id    BLOB NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message_id BLOB NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, message_id)
) STRICT, WITHOUT ROWID;

CREATE INDEX message_mentions_by_message ON message_mentions(message_id);
