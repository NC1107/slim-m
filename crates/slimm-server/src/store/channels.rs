// SPDX-License-Identifier: AGPL-3.0-only
//! Channel persistence: create, fetch, rename, and soft-delete.
//!
//! Listing lives in [`super::bootstrap`] alongside the rest of the admin
//! surface it was introduced with; this module is the CRUD paths for a
//! single channel.

use super::{Channel, Store, now_ms};
use crate::ids::ChannelId;

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

impl Store {
    /// Creates a channel and seeds its message and canvas sequence counters.
    ///
    /// Appended to the end of the deployment's channel order: one more than
    /// the highest position among live, non-DM channels, computed inside this
    /// same transaction so two concurrent creates cannot both claim the last
    /// slot. A DM's position is left at its schema default (0) and never
    /// read, since a DM is excluded from every position-ordered query.
    pub async fn create_channel(&self, name: &str, kind: &str) -> anyhow::Result<Channel> {
        let id = ChannelId::generate();
        let now = now_ms();
        let mut tx = self.begin_write().await?;
        let position = sqlx::query_scalar!(
            r#"SELECT COALESCE(MAX(position), -1) + 1 AS "next!: i64" FROM channels
               WHERE deleted_at IS NULL AND kind != 'dm'"#
        )
        .fetch_one(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO channels (id, name, kind, position, created_at) VALUES (?, ?, ?, ?, ?)",
            id,
            name,
            kind,
            position,
            now
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
        Ok(Channel {
            id,
            name: name.to_owned(),
            kind: kind.to_owned(),
            topic: None,
            position,
            created_at: now,
        })
    }

    /// Fetches a live channel by id, or `None` if it is missing or deleted.
    pub async fn channel(&self, id: ChannelId) -> anyhow::Result<Option<Channel>> {
        let row = sqlx::query!(
            r#"SELECT id AS "id!: ChannelId", name AS "name!", kind AS "kind!", topic,
                      position AS "position!: i64", created_at AS "created_at!"
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
    pub async fn channel_scopes_moderation(&self, id: ChannelId) -> anyhow::Result<bool> {
        Ok(match self.channel(id).await? {
            Some(channel) => channel.kind != super::dms::DM_CHANNEL_KIND,
            None => false,
        })
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
        let row = sqlx::query!(
            r#"SELECT id AS "id!: ChannelId", name AS "name!", kind AS "kind!", topic,
                      position AS "position!: i64", created_at AS "created_at!"
               FROM channels WHERE id = ?"#,
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
            created_at: r.created_at,
        }))
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
                 WHERE id = ? AND deleted_at IS NULL AND kind != 'dm'",
                name,
                topic,
                id
            )
            .execute(&self.pool)
            .await?
            .rows_affected(),
            (Some(name), None) => sqlx::query!(
                "UPDATE channels SET name = ? \
                 WHERE id = ? AND deleted_at IS NULL AND kind != 'dm'",
                name,
                id
            )
            .execute(&self.pool)
            .await?
            .rows_affected(),
            (None, Some(topic)) => sqlx::query!(
                "UPDATE channels SET topic = ? \
                 WHERE id = ? AND deleted_at IS NULL AND kind != 'dm'",
                topic,
                id
            )
            .execute(&self.pool)
            .await?
            .rows_affected(),
            (None, None) => {
                let exists = sqlx::query_scalar!(
                    r#"SELECT 1 AS "one!: i64" FROM channels
                       WHERE id = ? AND deleted_at IS NULL AND kind != 'dm'"#,
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
    pub async fn delete_channel(&self, id: ChannelId) -> Result<bool, DeleteChannelError> {
        let now = now_ms();
        let mut tx = self.pool.begin().await?;

        let affected = sqlx::query!(
            "UPDATE channels SET deleted_at = ?
             WHERE id = ? AND deleted_at IS NULL AND kind != 'dm'
               AND (SELECT COUNT(*) FROM channels
                    WHERE deleted_at IS NULL AND kind != 'dm') > 1",
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
