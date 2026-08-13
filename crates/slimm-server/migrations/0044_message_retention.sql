-- SPDX-License-Identifier: AGPL-3.0-only
-- An opt-in, deployment-wide window past which a message is pruned. `0`
-- (the default, and what every deployment keeps on upgrade) means keep
-- forever - the same "off means the feature does not run" shape 0033 gave
-- `analytics_enabled`, applied to a number rather than a boolean.
ALTER TABLE space_settings ADD COLUMN message_retention_days INTEGER NOT NULL DEFAULT 0
    CHECK (message_retention_days >= 0);

-- `message_ops` had no index reaching `created_at` at all, the exact gap
-- 0038 closed for `canvas_ops` after it made every sweep pass a full scan;
-- see `store/message_retention.rs` for the sweep this serves.
CREATE INDEX message_ops_created_at ON message_ops(created_at);

-- Same reasoning for `messages`: partial, matching `messages_channel_live`'s
-- own shape, since a soft-deleted row is exactly what the content-pruning
-- pass never wants to find.
CREATE INDEX messages_live_created_at ON messages(created_at) WHERE deleted_at IS NULL;
