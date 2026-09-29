// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Per-channel join-muted default: the setter for `channels.join_muted`.

use super::{Channel, Store};
use crate::ids::ChannelId;

impl Store {
    /// Sets a channel's join-muted default. Excludes a DM or a thread, like
    /// [`Store::update_channel`], so `None` means nothing matched.
    pub async fn update_channel_join_muted(
        &self,
        id: ChannelId,
        join_muted: bool,
    ) -> anyhow::Result<Option<Channel>> {
        let affected = sqlx::query!(
            "UPDATE channels SET join_muted = ? \
             WHERE id = ? AND deleted_at IS NULL AND kind != 'dm' \
             AND parent_message_id IS NULL",
            join_muted,
            id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if affected == 0 {
            return Ok(None);
        }
        self.channel(id).await
    }
}
