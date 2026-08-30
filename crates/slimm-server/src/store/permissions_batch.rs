// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The batched permission read paths: many candidates against one channel
//! (push fan-out), many channels against one caller (the rail listing and
//! `GET /channels`'s own bitmask), and many arbitrary channel ids against
//! one caller (the report queue's `channel_permissions` field).
//!
//! Split from `permissions.rs` when the batching pushed that file past the
//! 500-line ceiling. All three load a role context and a set of overwrites
//! with a bounded number of queries, then run the same pure
//! [`crate::permissions::evaluate`] the per-user path runs, and each carries
//! an equivalence test in `tests/permissions.rs` proving the answers
//! identical to asking the per-user path once per candidate.

use uuid::Uuid;

use super::Store;
use super::timeouts::TIMEOUT_DENY;
use crate::ids::{ChannelId, RoleId, UserId};
use crate::permissions::{Overwrite, Permissions, evaluate, mask_unless_viewable};

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
        // A thread has no overwrites of its own; see `permission_channel`.
        let Some(channel) = self.permission_channel(channel).await? else {
            return Ok(Vec::new());
        };
        let channel_id = channel.id;

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

    /// [`Self::visible_channels`], paired with each channel's own full
    /// effective bitmask - what `GET /channels`'s `permissions` field is
    /// populated from. Every row here already carries VIEW_CHANNEL by
    /// construction (this filters on exactly that bit, and every row came
    /// from [`Self::list_channels`] in the first place), so unlike the
    /// dedicated per-channel route and [`Self::permissions_in_channels`]
    /// below, there is no "channel does not exist" case a raw answer could
    /// be confused with, and nothing here needs
    /// [`crate::permissions::mask_unless_viewable`].
    pub async fn visible_channels_with_permissions(
        &self,
        user_id: UserId,
    ) -> anyhow::Result<Vec<(super::Channel, Permissions)>> {
        Ok(self
            .channel_permissions_all(user_id)
            .await?
            .into_iter()
            .filter(|(_, perms)| perms.contains(Permissions::VIEW_CHANNEL))
            .collect())
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
        Ok(self
            .channel_permissions_all(user_id)
            .await?
            .into_iter()
            .filter(|(_, perms)| perms.contains(needed))
            .map(|(channel, _)| channel)
            .collect())
    }

    /// The shared load-and-evaluate behind [`Self::channels_where`] and
    /// [`Self::visible_channels_with_permissions`]: every live channel's row
    /// paired with the caller's full effective bitmask in it, unfiltered.
    /// Both callers trim this to their own shape, so the query cost - one
    /// `load_roles` call and one batched overwrite fetch for however many
    /// channels exist - is paid once regardless of which is asked; this used
    /// to be `channels_where`'s own body before a second caller needed the
    /// bitmask itself rather than only a bool.
    async fn channel_permissions_all(
        &self,
        user_id: UserId,
    ) -> anyhow::Result<Vec<(super::Channel, Permissions)>> {
        let channels = self.list_channels().await?;
        if channels.is_empty() {
            return Ok(Vec::new());
        }
        let roles = self.load_roles(user_id).await?;
        // Hoisted: the map closure below is synchronous and cannot await.
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
            .map(|channel| {
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
                let perms = evaluate(
                    roles.everyone_perms,
                    &roles.role_perms,
                    everyone_overwrite,
                    &role_overwrites,
                    member_overwrite,
                )
                .remove(timeout_deny);
                (channel, perms)
            })
            .collect())
    }

    /// The caller's effective permissions in each of `channel_ids`, batched
    /// so a report page costs one shared query rather than one
    /// [`Self::permissions_in_channel`] call per report.
    ///
    /// Unlike [`Self::channels_where`], this does not start from
    /// [`Self::list_channels`] - it answers for exactly the ids it is asked
    /// about, which is what lets it reach a DM or a deleted channel:
    /// `list_channels` excludes both by construction (see
    /// docs/decisions/0005-threads.md), and those are precisely the two
    /// report cases docs/decisions/0011-per-channel-permissions.md names as
    /// needing this. Each id resolves independently: a thread through
    /// [`Self::permission_channel`], a DM through [`Self::dm_permissions`], a
    /// dead or nonexistent id to [`Permissions::NONE`], and everything else
    /// through the ordinary evaluator - sharing one [`Self::load_roles`] call
    /// and one `IN`-batched overwrite fetch across however many ordinary
    /// channels the page names. Masked with
    /// [`crate::permissions::mask_unless_viewable`], the same guard
    /// `http::channel_permissions` applies to its own answer and for the
    /// identical existence-probe reason.
    ///
    /// Query cost is this doc comment, not a test: this suite has no
    /// query-counting harness (checked; see docs/decisions/0011). Per call:
    /// one `timeout_deny`, one `load_roles`, one `channel` fetch per
    /// distinct requested id (a thread's parent needs a live read to find,
    /// so this cannot be pre-batched the way the overwrite fetch is), one
    /// `dm_permissions` call per distinct DM id in the page, and one batched
    /// overwrite query for the rest.
    pub async fn permissions_in_channels(
        &self,
        user_id: UserId,
        channel_ids: &[ChannelId],
    ) -> anyhow::Result<std::collections::HashMap<ChannelId, Permissions>> {
        use std::collections::HashMap;

        let mut result: HashMap<ChannelId, Permissions> = HashMap::new();
        if channel_ids.is_empty() {
            return Ok(result);
        }

        let timeout_deny = self.timeout_deny(user_id).await?;
        let roles = self.load_roles(user_id).await?;

        // The DM and dead/nonexistent branches are answered here, before the shared batched fetch below.
        let mut ordinary: Vec<(ChannelId, super::Channel)> = Vec::new();
        for &channel_id in channel_ids {
            if result.contains_key(&channel_id) {
                continue;
            }
            let Some(channel) = self.channel(channel_id).await? else {
                result.insert(channel_id, Permissions::NONE);
                continue;
            };
            // A thread has no overwrites of its own; see `permission_channel`.
            let Some(resolved) = self.permission_channel(channel).await? else {
                result.insert(channel_id, Permissions::NONE);
                continue;
            };
            if resolved.kind == super::dms::DM_CHANNEL_KIND {
                let permissions = self
                    .dm_permissions(user_id, resolved.id)
                    .await?
                    .remove(timeout_deny);
                result.insert(channel_id, mask_unless_viewable(permissions));
                continue;
            }
            ordinary.push((channel_id, resolved));
        }

        if ordinary.is_empty() {
            return Ok(result);
        }

        // One built query for the still-live channels' overwrites, deduplicated since several ids can share one.
        let mut resolved_ids: Vec<ChannelId> = ordinary.iter().map(|(_, c)| c.id).collect();
        resolved_ids.sort_by_key(|id| id.0);
        resolved_ids.dedup();

        let mut builder = sqlx::QueryBuilder::new(
            "SELECT channel_id, target_type, target_id, allow, deny \
             FROM channel_overwrites WHERE channel_id IN (",
        );
        let mut separated = builder.separated(", ");
        for id in &resolved_ids {
            separated.push_bind(*id);
        }
        builder.push(")");
        let rows = builder.build().fetch_all(&self.pool).await?;

        use sqlx::Row;
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
        for (requested_id, channel) in ordinary {
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
            let perms = evaluate(
                roles.everyone_perms,
                &roles.role_perms,
                everyone_overwrite,
                &role_overwrites,
                member_overwrite,
            )
            .remove(timeout_deny);
            result.insert(requested_id, mask_unless_viewable(perms));
        }

        Ok(result)
    }
}
