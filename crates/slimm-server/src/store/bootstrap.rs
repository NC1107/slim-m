// SPDX-License-Identifier: AGPL-3.0-only
//! First-run bootstrap and the channel and role management the admin surface
//! needs.
//!
//! A fresh deployment has no roles and no channels, so nobody can do anything.
//! The first account to register claims the deployment: it is granted an admin
//! role, an `@everyone` base role is seeded with the everyday permissions, and a
//! general channel is created. This is the self-hosted "first person to log in
//! becomes admin" model, and it runs exactly once because it is conditional on
//! there being no `@everyone` role yet.

use super::{Store, now_ms};
use crate::ids::{ChannelId, RoleId, UserId};
use crate::permissions::Permissions;

/// What `@everyone` gets on a fresh deployment: read and take part, but no
/// moderation or management.
const EVERYONE_DEFAULTS: Permissions = Permissions::VIEW_CHANNEL
    .union(Permissions::SEND_MESSAGES)
    .union(Permissions::ADD_REACTIONS)
    .union(Permissions::ATTACH_FILES)
    .union(Permissions::CONNECT)
    .union(Permissions::SPEAK)
    .union(Permissions::USE_CANVAS);

/// The outcome of a bootstrap attempt.
#[derive(Debug, PartialEq, Eq)]
pub enum Bootstrap {
    /// This account claimed the deployment and is now an administrator.
    Claimed,
    /// The deployment was already set up; nothing changed.
    AlreadySetUp,
}

impl Store {
    /// Claims an unclaimed deployment for `user_id`, seeding the `@everyone` and
    /// admin roles and a general channel.
    ///
    /// Concurrency: the `@everyone` insert is the transaction's first statement
    /// and the partial unique index on `is_everyone` makes it the claim. Two
    /// racing registrations therefore serialize, and the loser sees a unique
    /// violation and reports [`Bootstrap::AlreadySetUp`] rather than seeding a
    /// second set of roles.
    pub async fn bootstrap_deployment(&self, user_id: UserId) -> anyhow::Result<Bootstrap> {
        let now = now_ms();
        let mut tx = self.pool.begin().await?;

        let everyone_id = RoleId::generate();
        let everyone_bits = EVERYONE_DEFAULTS.bits();
        let claim = sqlx::query!(
            "INSERT INTO roles (id, name, permissions, is_everyone, created_at)
             VALUES (?, 'everyone', ?, 1, ?)",
            everyone_id,
            everyone_bits,
            now
        )
        .execute(&mut *tx)
        .await;

        match claim {
            Ok(_) => {}
            // Someone else already claimed it; leave their setup alone.
            Err(sqlx::Error::Database(e)) if e.is_unique_violation() => {
                return Ok(Bootstrap::AlreadySetUp);
            }
            Err(e) => return Err(e.into()),
        }

        let admin_id = RoleId::generate();
        let admin_bits = Permissions::ADMINISTRATOR.bits();
        sqlx::query!(
            "INSERT INTO roles (id, name, permissions, is_everyone, position, created_at)
             VALUES (?, 'admin', ?, 0, 100, ?)",
            admin_id,
            admin_bits,
            now
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO member_roles (user_id, role_id) VALUES (?, ?)",
            user_id,
            admin_id
        )
        .execute(&mut *tx)
        .await?;

        let channel_id = ChannelId::generate();
        sqlx::query!(
            "INSERT INTO channels (id, name, kind, created_at) VALUES (?, 'general', 'text', ?)",
            channel_id,
            now
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO channel_seq_counters (channel_id, stream, next_seq)
             VALUES (?, 'message', 1), (?, 'canvas', 1)",
            channel_id,
            channel_id
        )
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(Bootstrap::Claimed)
    }

    /// Whether this deployment has been claimed yet.
    pub async fn is_bootstrapped(&self) -> anyhow::Result<bool> {
        let found =
            sqlx::query_scalar!(r#"SELECT 1 AS "one!: i64" FROM roles WHERE is_everyone = 1"#)
                .fetch_optional(&self.pool)
                .await?;
        Ok(found.is_some())
    }

    /// Lists the deployment's live channels, oldest first.
    ///
    /// Excludes `dm`-kind channels: a DM is not a deployment channel anyone
    /// browses into, it is a conversation between exactly two people, listed
    /// instead by `Store::list_dm_conversations`. Filtering it out here,
    /// rather than trusting every caller of this method to do it themselves,
    /// is what keeps a DM out of the ordinary channel list even though it
    /// lives in the same table.
    pub async fn list_channels(&self) -> anyhow::Result<Vec<super::Channel>> {
        let rows = sqlx::query!(
            r#"SELECT id AS "id!: ChannelId", name AS "name!", kind AS "kind!", topic,
                      position AS "position!: i64", created_at AS "created_at!"
               FROM channels WHERE deleted_at IS NULL AND kind != 'dm'
               ORDER BY position, created_at"#
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| super::Channel {
                id: r.id,
                name: r.name,
                kind: r.kind,
                topic: r.topic,
                position: r.position,
                created_at: r.created_at,
            })
            .collect())
    }
}
