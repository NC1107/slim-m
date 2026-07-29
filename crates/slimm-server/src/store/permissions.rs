// SPDX-License-Identifier: AGPL-3.0-only
//! Role and overwrite persistence, and the effective-permission read path.
//!
//! The pure precedence logic lives in [`crate::permissions`]; this module loads
//! a user's roles and a channel's overwrites and feeds them to the evaluator.

use uuid::Uuid;

use super::{Store, now_ms};
use crate::ids::{ChannelId, RoleId, UserId};
use crate::permissions::{Overwrite, Permissions, evaluate};

/// A user's roles, resolved once and reused by both permission read paths.
struct RoleContext {
    everyone_id: Option<Uuid>,
    everyone_perms: Permissions,
    role_perms: Vec<Permissions>,
    role_ids: Vec<Uuid>,
}

impl Store {
    /// Creates a role. Exactly one role carries `is_everyone`; that base role
    /// applies to every member whether or not they hold it explicitly. A partial
    /// unique index enforces the singleton, so a second `@everyone` role is
    /// rejected here rather than corrupting the evaluation base.
    pub async fn create_role(
        &self,
        name: &str,
        permissions: Permissions,
        is_everyone: bool,
    ) -> anyhow::Result<RoleId> {
        let id = RoleId::generate();
        let now = now_ms();
        let bits = permissions.bits();
        let is_everyone = i64::from(is_everyone);
        let result = sqlx::query!(
            "INSERT INTO roles (id, name, permissions, is_everyone, created_at)
             VALUES (?, ?, ?, ?, ?)",
            id,
            name,
            bits,
            is_everyone,
            now
        )
        .execute(&self.pool)
        .await;

        match result {
            Ok(_) => Ok(id),
            Err(sqlx::Error::Database(e)) if e.is_unique_violation() => {
                anyhow::bail!("an @everyone role already exists")
            }
            Err(e) => Err(e.into()),
        }
    }

    /// Grants a role to a member. Idempotent.
    pub async fn assign_role(&self, user_id: UserId, role_id: RoleId) -> anyhow::Result<()> {
        sqlx::query!(
            "INSERT OR IGNORE INTO member_roles (user_id, role_id) VALUES (?, ?)",
            user_id,
            role_id
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Sets (or replaces) a channel overwrite for a role.
    pub async fn set_role_overwrite(
        &self,
        channel_id: ChannelId,
        role_id: RoleId,
        allow: Permissions,
        deny: Permissions,
    ) -> anyhow::Result<()> {
        self.set_overwrite(channel_id, "role", role_id.0, allow, deny)
            .await
    }

    /// Sets (or replaces) a channel overwrite for a single member.
    pub async fn set_member_overwrite(
        &self,
        channel_id: ChannelId,
        user_id: UserId,
        allow: Permissions,
        deny: Permissions,
    ) -> anyhow::Result<()> {
        self.set_overwrite(channel_id, "member", user_id.0, allow, deny)
            .await
    }

    async fn set_overwrite(
        &self,
        channel_id: ChannelId,
        target_type: &str,
        target_id: Uuid,
        allow: Permissions,
        deny: Permissions,
    ) -> anyhow::Result<()> {
        let allow = allow.bits();
        let deny = deny.bits();
        sqlx::query!(
            "INSERT INTO channel_overwrites (channel_id, target_type, target_id, allow, deny)
             VALUES (?, ?, ?, ?, ?)
             ON CONFLICT(channel_id, target_type, target_id)
             DO UPDATE SET allow = excluded.allow, deny = excluded.deny",
            channel_id,
            target_type,
            target_id,
            allow,
            deny
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// The overwrite currently set for one target in one channel, if any.
    ///
    /// Callers need this to work out what a write would actually grant.
    /// Judging an overwrite by its new `allow` bits alone misses that removing
    /// a `deny` grants that permission just as surely as adding an `allow`.
    pub async fn overwrite_for(
        &self,
        channel_id: ChannelId,
        target_type: &str,
        target_id: Uuid,
    ) -> anyhow::Result<Option<(Permissions, Permissions)>> {
        let row = sqlx::query!(
            r#"SELECT allow AS "allow!: i64", deny AS "deny!: i64"
               FROM channel_overwrites
               WHERE channel_id = ? AND target_type = ? AND target_id = ?"#,
            channel_id,
            target_type,
            target_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| {
            (
                Permissions::from_bits(r.allow),
                Permissions::from_bits(r.deny),
            )
        }))
    }

    /// Clears a channel's role overwrite. Idempotent: clearing one that is
    /// not set still succeeds, the same as removing a reaction that is not
    /// there does.
    pub async fn delete_role_overwrite(
        &self,
        channel_id: ChannelId,
        role_id: RoleId,
    ) -> anyhow::Result<()> {
        self.delete_overwrite(channel_id, "role", role_id.0).await
    }

    /// Clears a channel's member overwrite. Idempotent, the same way.
    pub async fn delete_member_overwrite(
        &self,
        channel_id: ChannelId,
        user_id: UserId,
    ) -> anyhow::Result<()> {
        self.delete_overwrite(channel_id, "member", user_id.0).await
    }

    async fn delete_overwrite(
        &self,
        channel_id: ChannelId,
        target_type: &str,
        target_id: Uuid,
    ) -> anyhow::Result<()> {
        sqlx::query!(
            "DELETE FROM channel_overwrites
             WHERE channel_id = ? AND target_type = ? AND target_id = ?",
            channel_id,
            target_type,
            target_id
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// The user's guild-level permissions, ignoring any channel. Applies the
    /// `@everyone` base, the role union, and the administrator bypass.
    pub async fn base_permissions(&self, user_id: UserId) -> anyhow::Result<Permissions> {
        let roles = self.load_roles(user_id).await?;
        Ok(evaluate(
            roles.everyone_perms,
            &roles.role_perms,
            None,
            &[],
            None,
        ))
    }

    /// The user's effective permissions in a specific channel, applying the base
    /// then the channel overwrites in precedence order.
    ///
    /// A channel that does not exist grants nothing. Without that, a probe for
    /// a fabricated channel id would inherit the base `@everyone` permissions
    /// (it has no overwrites) and be distinguishable from a real channel the
    /// caller may not view, which would leak channel existence.
    ///
    /// A direct-message channel does not run through the role and overwrite
    /// model at all: see [`Store::dm_permissions`] for why, and specifically
    /// why that has to hold even against ADMINISTRATOR, which the evaluator
    /// bypasses for every other channel on purpose.
    pub async fn permissions_in_channel(
        &self,
        user_id: UserId,
        channel_id: ChannelId,
    ) -> anyhow::Result<Permissions> {
        // A nonexistent channel grants nothing; see the note on this function.
        let Some(channel) = self.channel(channel_id).await? else {
            return Ok(Permissions::NONE);
        };

        // DMs skip the role and overwrite model; see the note on this function.
        if channel.kind == super::dms::DM_CHANNEL_KIND {
            return self.dm_permissions(user_id, channel_id).await;
        }

        let roles = self.load_roles(user_id).await?;

        let rows = sqlx::query!(
            r#"SELECT target_type,
                      target_id AS "target_id!: Uuid",
                      allow AS "allow!: Permissions",
                      deny AS "deny!: Permissions"
               FROM channel_overwrites WHERE channel_id = ?"#,
            channel_id
        )
        .fetch_all(&self.pool)
        .await?;

        let mut everyone_overwrite = None;
        let mut role_overwrites = Vec::new();
        let mut member_overwrite = None;
        for row in rows {
            let overwrite = Overwrite {
                allow: row.allow,
                deny: row.deny,
            };
            match row.target_type.as_str() {
                "role" if Some(row.target_id) == roles.everyone_id => {
                    everyone_overwrite = Some(overwrite);
                }
                "role" if roles.role_ids.contains(&row.target_id) => {
                    role_overwrites.push(overwrite);
                }
                "member" if row.target_id == user_id.0 => {
                    member_overwrite = Some(overwrite);
                }
                _ => {}
            }
        }

        Ok(evaluate(
            roles.everyone_perms,
            &roles.role_perms,
            everyone_overwrite,
            &role_overwrites,
            member_overwrite,
        ))
    }

    /// Live users who can view a channel: the recipient set for push fan-out.
    /// A nonexistent channel yields nobody, the same as [`Self::permissions_in_channel`].
    pub async fn channel_viewer_ids(&self, channel_id: ChannelId) -> anyhow::Result<Vec<UserId>> {
        let live = self.live_user_ids().await?;
        self.viewers_among(channel_id, &live).await
    }

    /// Which of `candidates` hold VIEW_CHANNEL in `channel_id`, answered with
    /// a bounded number of queries instead of a full evaluation per candidate.
    ///
    /// Push fan-out asked [`Self::has_permission`] once per push-registered
    /// user on every message, and each ask is its own channel fetch, two role
    /// queries and an overwrite fetch; on a busy channel that multiplied the
    /// per-message write-path work by the member count. This loads the
    /// channel, the @everyone role, every candidate's roles and the channel's
    /// overwrites once each, then runs the same pure [`evaluate`] per
    /// candidate, so the answers are identical by construction.
    ///
    /// A DM never reaches the evaluator, mirroring
    /// [`Self::permissions_in_channel`]: its pair is fetched once and only
    /// members of it are checked further, so the candidate count stops
    /// mattering there too.
    pub async fn viewers_among(
        &self,
        channel_id: ChannelId,
        candidates: &[UserId],
    ) -> anyhow::Result<Vec<UserId>> {
        if candidates.is_empty() {
            return Ok(Vec::new());
        }
        let Some(channel) = self.channel(channel_id).await? else {
            return Ok(Vec::new());
        };

        if channel.kind == super::dms::DM_CHANNEL_KIND {
            let mut viewers = Vec::new();
            // At most the two members of the pair survive dm_permissions, so
            // this loop is bounded at two real checks however long the list.
            for &user_id in candidates {
                if self
                    .dm_permissions(user_id, channel_id)
                    .await?
                    .contains(Permissions::VIEW_CHANNEL)
                {
                    viewers.push(user_id);
                }
            }
            return Ok(viewers);
        }

        let everyone = sqlx::query!(
            r#"SELECT id AS "id!: RoleId", permissions AS "permissions!: Permissions"
               FROM roles WHERE is_everyone = 1 LIMIT 1"#
        )
        .fetch_optional(&self.pool)
        .await?;
        let (everyone_id, everyone_perms) = match everyone {
            Some(row) => (Some(row.id.0), row.permissions),
            None => (None, Permissions::NONE),
        };

        // One batched query for every candidate's roles; SQLite has no array
        // binding, so it is built, the same shape roles_for_users uses.
        let mut builder = sqlx::QueryBuilder::new(
            "SELECT mr.user_id AS user_id, r.id AS role_id, r.permissions AS permissions \
             FROM roles r JOIN member_roles mr ON mr.role_id = r.id \
             WHERE r.is_everyone = 0 AND mr.user_id IN (",
        );
        let mut separated = builder.separated(", ");
        for id in candidates {
            separated.push_bind(*id);
        }
        builder.push(")");
        let role_rows = builder.build().fetch_all(&self.pool).await?;

        use sqlx::Row;
        use std::collections::HashMap;
        let mut roles_by_user: HashMap<Uuid, (Vec<Permissions>, Vec<Uuid>)> = HashMap::new();
        for row in role_rows {
            let user_id: Uuid = row.try_get("user_id")?;
            let role_id: Uuid = row.try_get("role_id")?;
            let perms: Permissions = row.try_get("permissions")?;
            let entry = roles_by_user.entry(user_id).or_default();
            entry.0.push(perms);
            entry.1.push(role_id);
        }

        let overwrite_rows = sqlx::query!(
            r#"SELECT target_type,
                      target_id AS "target_id!: Uuid",
                      allow AS "allow!: Permissions",
                      deny AS "deny!: Permissions"
               FROM channel_overwrites WHERE channel_id = ?"#,
            channel_id
        )
        .fetch_all(&self.pool)
        .await?;

        let empty: (Vec<Permissions>, Vec<Uuid>) = (Vec::new(), Vec::new());
        let mut viewers = Vec::new();
        for &user_id in candidates {
            let (role_perms, role_ids) = roles_by_user.get(&user_id.0).unwrap_or(&empty);

            let mut everyone_overwrite = None;
            let mut role_overwrites = Vec::new();
            let mut member_overwrite = None;
            for row in &overwrite_rows {
                let overwrite = Overwrite {
                    allow: row.allow,
                    deny: row.deny,
                };
                match row.target_type.as_str() {
                    "role" if Some(row.target_id) == everyone_id => {
                        everyone_overwrite = Some(overwrite);
                    }
                    "role" if role_ids.contains(&row.target_id) => {
                        role_overwrites.push(overwrite);
                    }
                    "member" if row.target_id == user_id.0 => {
                        member_overwrite = Some(overwrite);
                    }
                    _ => {}
                }
            }

            let perms = evaluate(
                everyone_perms,
                role_perms,
                everyone_overwrite,
                &role_overwrites,
                member_overwrite,
            );
            if perms.contains(Permissions::VIEW_CHANNEL) {
                viewers.push(user_id);
            }
        }
        Ok(viewers)
    }

    /// The channels this user can view, in rail order: [`Store::list_channels`]
    /// filtered by VIEW_CHANNEL with the caller's role context loaded once.
    ///
    /// The handler used to ask [`Self::has_permission`] per channel, which
    /// re-fetched the channel row it already held and the same role context
    /// every iteration - 1 + 4C queries for C channels on a request every
    /// client fires at startup. This is four queries however many channels
    /// exist, evaluated by the same pure [`evaluate`].
    pub async fn visible_channels(&self, user_id: UserId) -> anyhow::Result<Vec<super::Channel>> {
        let channels = self.list_channels().await?;
        if channels.is_empty() {
            return Ok(channels);
        }
        let roles = self.load_roles(user_id).await?;

        // One query for every listed channel's overwrites; built because the
        // id list is variable length and SQLite has no array binding.
        let mut builder = sqlx::QueryBuilder::new(
            "SELECT channel_id, target_type, target_id, allow, deny \
             FROM channel_overwrites WHERE channel_id IN (",
        );
        let mut separated = builder.separated(", ");
        for channel in &channels {
            separated.push_bind(channel.id);
        }
        builder.push(")");
        let rows = builder.build().fetch_all(&self.pool).await?;

        use sqlx::Row;
        use std::collections::HashMap;
        struct RawOverwrite {
            target_type: String,
            target_id: Uuid,
            overwrite: Overwrite,
        }
        let mut by_channel: HashMap<Uuid, Vec<RawOverwrite>> = HashMap::new();
        for row in rows {
            let channel_id: Uuid = row.try_get("channel_id")?;
            by_channel
                .entry(channel_id)
                .or_default()
                .push(RawOverwrite {
                    target_type: row.try_get("target_type")?,
                    target_id: row.try_get("target_id")?,
                    overwrite: Overwrite {
                        allow: row.try_get("allow")?,
                        deny: row.try_get("deny")?,
                    },
                });
        }

        let empty = Vec::new();
        Ok(channels
            .into_iter()
            .filter(|channel| {
                let mut everyone_overwrite = None;
                let mut role_overwrites = Vec::new();
                let mut member_overwrite = None;
                for raw in by_channel.get(&channel.id.0).unwrap_or(&empty) {
                    match raw.target_type.as_str() {
                        "role" if Some(raw.target_id) == roles.everyone_id => {
                            everyone_overwrite = Some(raw.overwrite);
                        }
                        "role" if roles.role_ids.contains(&raw.target_id) => {
                            role_overwrites.push(raw.overwrite);
                        }
                        "member" if raw.target_id == user_id.0 => {
                            member_overwrite = Some(raw.overwrite);
                        }
                        _ => {}
                    }
                }
                evaluate(
                    roles.everyone_perms,
                    &roles.role_perms,
                    everyone_overwrite,
                    &role_overwrites,
                    member_overwrite,
                )
                .contains(Permissions::VIEW_CHANNEL)
            })
            .collect())
    }

    /// Whether the user holds every bit in `needed` in this channel.
    pub async fn has_permission(
        &self,
        user_id: UserId,
        channel_id: ChannelId,
        needed: Permissions,
    ) -> anyhow::Result<bool> {
        Ok(self
            .permissions_in_channel(user_id, channel_id)
            .await?
            .contains(needed))
    }

    async fn load_roles(&self, user_id: UserId) -> anyhow::Result<RoleContext> {
        // At most one @everyone role exists (a partial unique index enforces it),
        // so LIMIT 1 resolves the base deterministically.
        let everyone = sqlx::query!(
            r#"SELECT id AS "id!: RoleId", permissions AS "permissions!: Permissions"
               FROM roles WHERE is_everyone = 1 LIMIT 1"#
        )
        .fetch_optional(&self.pool)
        .await?;
        let (everyone_id, everyone_perms) = match everyone {
            Some(row) => (Some(row.id.0), row.permissions),
            None => (None, Permissions::NONE),
        };

        let rows = sqlx::query!(
            r#"SELECT r.id AS "id!: RoleId", r.permissions AS "permissions!: Permissions"
               FROM roles r
               JOIN member_roles mr ON mr.role_id = r.id
               WHERE mr.user_id = ? AND r.is_everyone = 0"#,
            user_id
        )
        .fetch_all(&self.pool)
        .await?;

        let role_perms = rows.iter().map(|r| r.permissions).collect();
        let role_ids = rows.iter().map(|r| r.id.0).collect();

        Ok(RoleContext {
            everyone_id,
            everyone_perms,
            role_perms,
            role_ids,
        })
    }
}
