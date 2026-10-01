// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! One write for everything `PATCH /channels/{id}` can change, so a failure
//! cannot leave some fields applied and the rest not.

use sqlx::QueryBuilder;

use super::{Channel, Store};
use crate::ids::ChannelId;

/// The fields a channel update may set; `None` leaves a field untouched.
#[derive(Default)]
pub struct ChannelPatch<'a> {
    pub name: Option<&'a str>,
    /// `Some(None)` clears the topic.
    pub topic: Option<Option<&'a str>>,
    pub slow_mode_seconds: Option<i64>,
    /// A default, not a lock: SPEAK overwrites are what restrict speaking.
    pub join_muted: Option<bool>,
}

impl Store {
    /// Applies `patch` in one statement. `None` means nothing matched: the
    /// channel is missing, deleted, a DM or a thread, the same guard
    /// [`Store::update_channel`] applies.
    pub async fn update_channel_settings(
        &self,
        id: ChannelId,
        patch: ChannelPatch<'_>,
    ) -> anyhow::Result<Option<Channel>> {
        let mut builder = QueryBuilder::new("UPDATE channels SET ");
        let mut set = builder.separated(", ");
        if let Some(name) = patch.name {
            set.push("name = ").push_bind_unseparated(name.to_owned());
        }
        if let Some(topic) = patch.topic {
            set.push("topic = ")
                .push_bind_unseparated(topic.map(str::to_owned));
        }
        if let Some(seconds) = patch.slow_mode_seconds {
            set.push("slow_mode_seconds = ")
                .push_bind_unseparated(seconds);
        }
        if let Some(join_muted) = patch.join_muted {
            set.push("join_muted = ").push_bind_unseparated(join_muted);
        }
        if patch.name.is_none()
            && patch.topic.is_none()
            && patch.slow_mode_seconds.is_none()
            && patch.join_muted.is_none()
        {
            return self.update_channel(id, None, None).await;
        }
        builder.push(" WHERE id = ").push_bind(id);
        builder.push(" AND deleted_at IS NULL AND kind != 'dm' AND parent_message_id IS NULL");
        let affected = builder.build().execute(&self.pool).await?.rows_affected();
        if affected == 0 {
            return Ok(None);
        }
        self.channel(id).await
    }
}
