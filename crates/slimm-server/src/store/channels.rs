// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Channel persistence: create, fetch, rename, and soft-delete.
//!
//! Listing lives in [`super::bootstrap`] alongside the rest of the admin
//! surface it was introduced with; this module is the CRUD paths for a
//! single channel.

use sqlx::SqliteExecutor;

use super::{Channel, Store, now_ms};
use crate::ids::{ChannelCategoryId, ChannelId};

/// Why deleting a channel failed.
#[derive(Debug)]
pub enum DeleteChannelError {
    /// This is the deployment's last live channel. Refused rather than
    /// honoured: a deployment with zero channels has nowhere for anyone to
    /// land, the same reason bootstrap seeds a `general` channel for a fresh
    /// deployment in the first place.
    LastChannel,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for DeleteChannelError {
    fn from(err: sqlx::Error) -> Self {
        DeleteChannelError::Internal(err.into())
    }
}

/// Why creating a channel by id failed outright, rather than succeeding
/// fresh or as a retry.
#[derive(Debug)]
pub enum CreateChannelError {
    /// This id already names a DM or a thread, not a POST /channels-creatable
    /// channel. `channels` holds all three kinds under one id namespace, so a
    /// colliding id must never be handed back as if it were the caller's own
    /// text/voice channel - the same reason
    /// [`super::messages::SendError::IdConflict`] refuses to alias a foreign
    /// message rather than returning it.
    IdConflict,
    /// `category_id` named a category that does not exist. Refused rather
    /// than filed as uncategorised: a client asking for a specific section
    /// and silently getting a different one is worse than an error it can
    /// show.
    UnknownCategory,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for CreateChannelError {
    fn from(err: sqlx::Error) -> Self {
        CreateChannelError::Internal(err.into())
    }
}

impl From<anyhow::Error> for CreateChannelError {
    fn from(err: anyhow::Error) -> Self {
        CreateChannelError::Internal(err)
    }
}

/// The outcome of a create, which is idempotent by client-supplied id and so
/// may be a retry; see [`Store::create_channel_with_id`].
#[derive(Debug, Clone)]
pub struct CreatedChannel {
    pub channel: Channel,
    /// False when this id already named a channel, so the call was a retry
    /// of a create that already succeeded. The caller publishes
    /// `ChannelCreated` only when this is true, or a retry would wake every
    /// connected client a second time for a channel they already know about.
    pub fresh: bool,
}

impl Store {
    /// Creates a channel and seeds its message and canvas sequence counters.
    /// Idempotent by `id`: a retry with the same id returns the row already
    /// stored under it rather than inserting again, the same contract
    /// [`super::messages::Store::send_message`] gives a message send.
    ///
    /// [`Store::create_channel`] is the convenience form for a caller with no
    /// client-supplied id of its own; it mints one and always sees
    /// [`CreatedChannel::fresh`] true, since a freshly generated UUIDv7 id
    /// cannot already be in use.
    ///
    /// Appended to the end of the deployment's channel order: one more than
    /// the highest position among live, non-DM, non-thread channels,
    /// computed inside this same transaction so two concurrent creates
    /// cannot both claim the last slot. A DM's or a thread's position is
    /// left at its schema default (0) and never read, since both are
    /// excluded from every position-ordered query - the same exclusion
    /// [`super::bootstrap::Store::list_channels`] and
    /// [`super::channel_order::Store::reorder_channels`] already apply.
    ///
    /// Uses [`Store::begin_write`] (`BEGIN IMMEDIATE`) rather than a deferred
    /// transaction, for the same reason [`super::messages::Store::send_message`]
    /// does: this reads the id before it writes.
    ///
    /// The id probe matches a deleted row as well as a live one: the id
    /// column is unique either way, so a retry of a create whose channel was
    /// since removed must still match here and come back as the retry it is,
    /// rather than fall through to an INSERT that hits the unique id and
    /// maps to a 500.
    ///
    /// `channels` also holds DM channels and threads (a thread is a channel
    /// with `parent_message_id` set), neither of which this route can create
    /// or return: a match is only a retry when it is the same
    /// text/voice-and-top-level shape this call itself would have inserted,
    /// otherwise it is [`CreateChannelError::IdConflict`] rather than a 500
    /// or a wrong-typed 200.
    pub async fn create_channel_with_id(
        &self,
        id: ChannelId,
        name: &str,
        kind: &str,
        category_id: Option<ChannelCategoryId>,
    ) -> Result<CreatedChannel, CreateChannelError> {
        let now = now_ms();
        let mut tx = self.begin_write().await?;

        // Probes including a deleted row; see this function's doc for why.
        if let Some(existing) = fetch_channel_by_id(&mut *tx, id).await? {
            tx.commit().await?;
            let creatable_kind = matches!(existing.kind.as_str(), "text" | "voice")
                && existing.parent_message_id.is_none();
            if !creatable_kind {
                return Err(CreateChannelError::IdConflict);
            }
            return Ok(CreatedChannel {
                channel: existing,
                fresh: false,
            });
        }

        let position = sqlx::query_scalar!(
            r#"SELECT COALESCE(MAX(position), -1) + 1 AS "next!: i64" FROM channels
               WHERE deleted_at IS NULL AND kind != 'dm' AND parent_message_id IS NULL"#
        )
        .fetch_one(&mut *tx)
        .await?;
        // Checked by hand: the column's bare `REFERENCES` fails the insert with an error the caller cannot tell from any other.
        if let Some(category_id) = category_id {
            let known = sqlx::query_scalar!(
                r#"SELECT 1 AS "hit!: i64" FROM channel_categories WHERE id = ?"#,
                category_id
            )
            .fetch_optional(&mut *tx)
            .await?;
            if known.is_none() {
                tx.commit().await?;
                return Err(CreateChannelError::UnknownCategory);
            }
        }

        sqlx::query!(
            "INSERT INTO channels (id, name, kind, position, created_at, category_id) \
             VALUES (?, ?, ?, ?, ?, ?)",
            id,
            name,
            kind,
            position,
            now,
            category_id
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO channel_seq_counters (channel_id, stream, next_seq)
             VALUES (?, 'message', 1), (?, 'canvas', 1)",
            id,
            id
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(CreatedChannel {
            channel: Channel {
                id,
                name: name.to_owned(),
                kind: kind.to_owned(),
                topic: None,
                position,
                parent_message_id: None,
                // Whatever the caller filed it under; there is no default category (docs/decisions/0006).
                category_id,
                created_at: now,
            },
            fresh: true,
        })
    }

    /// Creates a channel with a server-minted id; see
    /// [`Store::create_channel_with_id`] for the idempotent form a caller
    /// with a client-supplied id wants instead.
    ///
    /// [`CreateChannelError::IdConflict`] cannot happen here: a freshly
    /// generated UUIDv7 cannot already name a DM or a thread. Neither can
    /// [`CreateChannelError::UnknownCategory`], since this form never names
    /// a category. The only error this ever actually surfaces is `Internal`.
    pub async fn create_channel(&self, name: &str, kind: &str) -> anyhow::Result<Channel> {
        match self
            .create_channel_with_id(ChannelId::generate(), name, kind, None)
            .await
        {
            Ok(created) => Ok(created.channel),
            Err(CreateChannelError::IdConflict) => {
                anyhow::bail!("a freshly generated channel id collided with an existing row")
            }
            Err(CreateChannelError::UnknownCategory) => {
                anyhow::bail!("uncategorised create reported an unknown category")
            }
            Err(CreateChannelError::Internal(err)) => Err(err),
        }
    }

    /// Fetches a live channel by id, or `None` if it is missing or deleted.
    pub async fn channel(&self, id: ChannelId) -> anyhow::Result<Option<Channel>> {
        let row = sqlx::query!(
            r#"SELECT id AS "id!: ChannelId", name AS "name!", kind AS "kind!", topic,
                      position AS "position!: i64",
                      parent_message_id AS "parent_message_id: crate::ids::MessageId",
                      category_id AS "category_id: crate::ids::ChannelCategoryId",
                      created_at AS "created_at!"
               FROM channels WHERE id = ? AND deleted_at IS NULL"#,
            id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| Channel {
            id: r.id,
            name: r.name,
            kind: r.kind,
            topic: r.topic,
            position: r.position,
            parent_message_id: r.parent_message_id,
            category_id: r.category_id,
            created_at: r.created_at,
        }))
    }

    /// Whether a channel can scope moderation to moderators of its own.
    ///
    /// A live text or voice channel can: a member holding `MANAGE_MESSAGES`
    /// there is a moderator of it, and a report about a message there is
    /// theirs to see. A DM cannot, because it has no moderators, only its
    /// pair; a deleted channel no longer can. A report about either belongs to
    /// the deployment's moderators, so this answers false and the caller falls
    /// back to the base check they already passed rather than a per-channel
    /// check that a DM or a gone channel grants to nobody.
    ///
    /// A thread resolves to the channel its parent message lives in, through
    /// [`Store::permission_channel`] - the same resolution every other
    /// permission check in this codebase already applies, rather than a
    /// second copy of it. It answered `false` unconditionally here until this
    /// was fixed, the same as a DM: a thread carries no `channel_overwrites`
    /// bucket of its own, so asking about it directly had nothing to
    /// evaluate. That let a moderator explicitly denied `MANAGE_MESSAGES` on
    /// a channel by overwrite still see, and resolve, reports about messages
    /// inside that channel's threads - the report queue's per-channel
    /// exclusion was never applied to them at all.
    pub async fn channel_scopes_moderation(&self, id: ChannelId) -> anyhow::Result<bool> {
        let Some(channel) = self.channel(id).await? else {
            return Ok(false);
        };
        let Some(channel) = self.permission_channel(channel).await? else {
            return Ok(false);
        };
        Ok(channel.kind != super::dms::DM_CHANNEL_KIND)
    }

    /// Fetches a channel by id whether or not it is deleted. The delete
    /// handler needs this rather than [`Store::channel`] to tell "never
    /// existed" (a 404) apart from "already deleted" (an idempotent no-op),
    /// which a `deleted_at`-filtered read cannot distinguish, the same
    /// reason [`Store::message_including_deleted`] exists.
    pub async fn channel_including_deleted(
        &self,
        id: ChannelId,
    ) -> anyhow::Result<Option<Channel>> {
        fetch_channel_by_id(&self.pool, id).await
    }

    /// Renames a channel and/or replaces its topic. `None` for either leaves
    /// that field untouched; `Some(None)` for `topic` clears it. Returns
    /// `None` if the channel does not exist (or was deleted, racing this
    /// call). Callers are expected to reject the case where both are `None`
    /// before reaching here (there is nothing to update), the same
    /// convention [`super::roles::update_role`] follows for its own two
    /// optional fields; this still resolves it safely as a plain existence
    /// check rather than assuming it can't happen.
    /// A DM is a channel of kind `dm` in this same table, and it is deliberately
    /// unreachable here: its only access rule is membership of the pair
    /// ([`super::dms`]), while these management routes gate on deployment-wide
    /// `MANAGE_CHANNELS`. Excluding it in SQL rather than at the call site is the
    /// same choice `list_channels` made, and for the same reason - the guard
    /// holds however many handlers end up calling this.
    pub async fn update_channel(
        &self,
        id: ChannelId,
        name: Option<&str>,
        topic: Option<Option<&str>>,
    ) -> anyhow::Result<Option<Channel>> {
        let affected = match (name, topic) {
            (Some(name), Some(topic)) => sqlx::query!(
                "UPDATE channels SET name = ?, topic = ? \
                 WHERE id = ? AND deleted_at IS NULL AND kind != 'dm' \
                 AND parent_message_id IS NULL",
                name,
                topic,
                id
            )
            .execute(&self.pool)
            .await?
            .rows_affected(),
            (Some(name), None) => sqlx::query!(
                "UPDATE channels SET name = ? \
                 WHERE id = ? AND deleted_at IS NULL AND kind != 'dm' \
                 AND parent_message_id IS NULL",
                name,
                id
            )
            .execute(&self.pool)
            .await?
            .rows_affected(),
            (None, Some(topic)) => sqlx::query!(
                "UPDATE channels SET topic = ? \
                 WHERE id = ? AND deleted_at IS NULL AND kind != 'dm' \
                 AND parent_message_id IS NULL",
                topic,
                id
            )
            .execute(&self.pool)
            .await?
            .rows_affected(),
            (None, None) => {
                let exists = sqlx::query_scalar!(
                    r#"SELECT 1 AS "one!: i64" FROM channels
                       WHERE id = ? AND deleted_at IS NULL AND kind != 'dm'
                         AND parent_message_id IS NULL"#,
                    id
                )
                .fetch_optional(&self.pool)
                .await?;
                u64::from(exists.is_some())
            }
        };
        if affected == 0 {
            return Ok(None);
        }
        self.channel(id).await
    }

    /// Soft-deletes a channel, refusing to remove the deployment's last live
    /// one. Returns whether this call performed the delete, so a retry
    /// against an already-deleted channel is idempotent rather than an error.
    ///
    /// Write-first: the single `UPDATE` both claims the row and enforces the
    /// last-channel guard in its `WHERE` clause, so two concurrent deletes of
    /// the deployment's last two channels cannot both succeed and leave zero.
    /// A separate "count, then decide, then delete" would race exactly there.
    /// Excludes `dm` channels for the reason given on [`Self::update_channel`].
    /// Note the last-channel guard counts only non-DM channels: otherwise a
    /// deployment could delete its final real channel as long as one DM existed,
    /// leaving members with nowhere to talk.
    ///
    /// The guard is also skipped entirely when the row being deleted is itself
    /// a thread. Excluding threads from the *count* was never enough: the guard
    /// still applied to the thread's own deletion, so a deployment sitting on
    /// one real channel could not delete any thread at all, having done nothing
    /// wrong. Deleting a thread cannot reduce the number of real channels, so
    /// there is nothing here for it to protect.
    ///
    /// It excludes a thread's own channels from that same count for the
    /// identical reason: a thread is never where anyone lands, and without
    /// this a deployment holding a handful of threads on its one real channel
    /// could have that channel deleted while the count still reads above one -
    /// see docs/decisions/0005-threads.md.
    pub async fn delete_channel(&self, id: ChannelId) -> Result<bool, DeleteChannelError> {
        let now = now_ms();
        let mut tx = self.pool.begin().await?;

        let affected = sqlx::query!(
            "UPDATE channels SET deleted_at = ?
             WHERE id = ? AND deleted_at IS NULL AND kind != 'dm'
               AND (parent_message_id IS NOT NULL
                    OR (SELECT COUNT(*) FROM channels
                        WHERE deleted_at IS NULL AND kind != 'dm'
                          AND parent_message_id IS NULL) > 1)",
            now,
            id
        )
        .execute(&mut *tx)
        .await?
        .rows_affected();

        if affected > 0 {
            tx.commit().await?;
            return Ok(true);
        }

        // The UPDATE matched nothing: tell "already gone" (idempotent no-op)
        // apart from "still live and alone" (the last-channel guard fired).
        let still_live = sqlx::query_scalar!(
            r#"SELECT 1 AS "one!: i64" FROM channels WHERE id = ? AND deleted_at IS NULL"#,
            id
        )
        .fetch_optional(&mut *tx)
        .await?
        .is_some();
        tx.commit().await?;

        if still_live {
            Err(DeleteChannelError::LastChannel)
        } else {
            Ok(false)
        }
    }
}

/// Fetches a channel by id, live or deleted, over any executor - the pool for
/// [`Store::channel_including_deleted`], or an open transaction for the id
/// probe inside [`Store::create_channel_with_id`].
async fn fetch_channel_by_id<'e, E>(executor: E, id: ChannelId) -> anyhow::Result<Option<Channel>>
where
    E: SqliteExecutor<'e>,
{
    let row = sqlx::query!(
        r#"SELECT id AS "id!: ChannelId", name AS "name!", kind AS "kind!", topic,
                  position AS "position!: i64",
                  parent_message_id AS "parent_message_id: crate::ids::MessageId",
                  category_id AS "category_id: crate::ids::ChannelCategoryId",
                  created_at AS "created_at!"
           FROM channels WHERE id = ?"#,
        id
    )
    .fetch_optional(executor)
    .await?;
    Ok(row.map(|r| Channel {
        id: r.id,
        name: r.name,
        kind: r.kind,
        topic: r.topic,
        position: r.position,
        parent_message_id: r.parent_message_id,
        category_id: r.category_id,
        created_at: r.created_at,
    }))
}
