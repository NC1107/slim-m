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
    pub async fn permissions_in_channel(
        &self,
        user_id: UserId,
        channel_id: ChannelId,
    ) -> anyhow::Result<Permissions> {
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
