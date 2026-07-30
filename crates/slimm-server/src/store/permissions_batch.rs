// SPDX-License-Identifier: AGPL-3.0-only
//! The batched permission read paths: many candidates against one channel
//! (push fan-out) and many channels against one caller (the rail listing).
//!
//! Split from `permissions.rs` when the batching pushed that file past the
//! 500-line ceiling. Both load a role context and a set of overwrites with a
//! bounded number of queries, then run the same pure
//! [`crate::permissions::evaluate`] the per-user path runs, and both carry an
//! equivalence test in `tests/permissions.rs` proving the answers identical.

use uuid::Uuid;

use super::Store;
use super::timeouts::TIMEOUT_DENY;
use crate::ids::{ChannelId, RoleId, UserId};
use crate::permissions::{Overwrite, Permissions, evaluate};

impl Store {
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
    /// [`Self::permissions_in_channel`]. Its pair is fetched once here and the
    /// candidates are narrowed to it before anything else is asked, so the
    /// candidate count stops mattering on that branch too.
    ///
    /// It did not, until 2026-07-30. This doc comment and the one inside the
    /// branch both claimed the loop was bounded at two real checks while it ran
    /// `dm_permissions` - itself a `dm_channels` lookup plus up to two block
    /// lookups - once per candidate. The cost was negligible in practice, since
    /// the candidates are a self-host's push-registered users, which is exactly
    /// why nothing caught it; a comment stating a bound that is not there is
    /// worse than no comment, because the next reader believes it and looks
    /// somewhere else.
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

        // One query: asking per candidate restores the cost this function removes.
        let timed_out = self.timed_out_among_until(candidates).await?;
        let deny_for = |user_id: UserId| {
            if timed_out.contains_key(&user_id) {
                TIMEOUT_DENY
            } else {
                Permissions::NONE
            }
        };

        if channel.kind == super::dms::DM_CHANNEL_KIND {
            let Some((user_a, user_b)) = self.dm_pair(channel_id).await? else {
                return Ok(Vec::new());
            };
            let mut viewers = Vec::new();
            // Narrowed to the pair first, so this really is at most two checks.
            for &user_id in candidates {
                if user_id != user_a && user_id != user_b {
                    continue;
                }
                if self
                    .dm_permissions(user_id, channel_id)
                    .await?
                    .remove(deny_for(user_id))
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

        // One built query for every candidate's roles (no array binding in SQLite), the same shape roles_for_users uses.
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
            )
            .remove(deny_for(user_id));
            if perms.contains(Permissions::VIEW_CHANNEL) {
                viewers.push(user_id);
            }
        }
        Ok(viewers)
    }

    /// The channels this user can view, in rail order.
    pub async fn visible_channels(&self, user_id: UserId) -> anyhow::Result<Vec<super::Channel>> {
        self.channels_where(user_id, Permissions::VIEW_CHANNEL)
            .await
    }

    /// [`Store::list_channels`] filtered by `needed`, with the caller's role
    /// context loaded once. DMs and deleted channels are outside it, because
    /// they are outside `list_channels`.
    ///
    /// The rail handler used to ask [`Self::has_permission`] per channel, which
    /// re-fetched the channel row it already held and the same role context
    /// every iteration - 1 + 4C queries for C channels on a request every
    /// client fires at startup. This is four queries however many channels
    /// exist, evaluated by the same pure [`evaluate`]. The moderation queue
    /// asks the same question about MANAGE_MESSAGES, which is why the
    /// permission is a parameter rather than the VIEW_CHANNEL this started as.
    pub async fn channels_where(
        &self,
        user_id: UserId,
        needed: Permissions,
    ) -> anyhow::Result<Vec<super::Channel>> {
        let channels = self.list_channels().await?;
        if channels.is_empty() {
            return Ok(channels);
        }
        let roles = self.load_roles(user_id).await?;
        // Hoisted: the filter closure below is synchronous and cannot await.
        let timeout_deny = self.timeout_deny(user_id).await?;

        // One built query for every listed channel's overwrites (no array binding in SQLite).
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
                .remove(timeout_deny)
                .contains(needed)
            })
            .collect())
    }
}
