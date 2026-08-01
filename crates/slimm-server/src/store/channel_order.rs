// SPDX-License-Identifier: AGPL-3.0-only
//! Setting the deployment's channel order: one caller-supplied list, applied
//! atomically, rather than a position PATCH per channel that could interleave
//! with another admin's drag and leave the order neither of them asked for.

use std::collections::HashSet;

use super::{Channel, Store};
use crate::ids::ChannelId;

/// Why setting the channel order failed.
#[derive(Debug)]
pub enum ReorderChannelsError {
    /// The given list did not name exactly the live, non-DM channels: some
    /// were repeated, some live channels were left out, or some named ids are
    /// not live, non-DM channels at all. `missing` and `extra` are each empty
    /// unless that half of the mismatch applies.
    Mismatch {
        missing: Vec<ChannelId>,
        extra: Vec<ChannelId>,
    },
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for ReorderChannelsError {
    fn from(err: sqlx::Error) -> Self {
        ReorderChannelsError::Internal(err.into())
    }
}

impl From<anyhow::Error> for ReorderChannelsError {
    fn from(err: anyhow::Error) -> Self {
        ReorderChannelsError::Internal(err)
    }
}

/// The result of a successful reorder.
pub struct ReorderOutcome {
    /// Every live, non-DM channel, in its new order.
    pub channels: Vec<Channel>,
    /// Which channels actually changed position. A caller submitting the
    /// order it already has gets an empty list rather than one claiming
    /// every channel moved - mirrors `edit_message` declining to mint a
    /// change nobody made.
    pub moved: Vec<ChannelId>,
}

impl Store {
    /// Sets the deployment's channel order to exactly `ordered`: position `i`
    /// for the channel at index `i`. Refuses a list that is not exactly the
    /// live, non-DM channels - too few would leave a gap nothing else fills,
    /// too many or a repeat names something this route cannot place - so a
    /// caller always knows whether its drag actually took effect.
    ///
    /// One transaction from the first read (see [`Store::begin_write`]), so a
    /// concurrent create or delete cannot land between the validation and the
    /// write and silently invalidate it.
    pub async fn reorder_channels(
        &self,
        ordered: &[ChannelId],
    ) -> Result<ReorderOutcome, ReorderChannelsError> {
        let mut tx = self.begin_write().await?;

        let live: Vec<ChannelId> = sqlx::query_scalar!(
            r#"SELECT id AS "id!: ChannelId" FROM channels
               WHERE deleted_at IS NULL AND kind != 'dm' AND parent_message_id IS NULL
               ORDER BY position, created_at"#
        )
        .fetch_all(&mut *tx)
        .await?;

        let live_set: HashSet<ChannelId> = live.iter().copied().collect();
        let given_set: HashSet<ChannelId> = ordered.iter().copied().collect();
        if given_set.len() != ordered.len() || live_set != given_set {
            return Err(ReorderChannelsError::Mismatch {
                missing: live_set.difference(&given_set).copied().collect(),
                extra: given_set.difference(&live_set).copied().collect(),
            });
        }

        let moved: Vec<ChannelId> = live
            .iter()
            .zip(ordered.iter())
            .filter(|(before, after)| before != after)
            .map(|(_, after)| *after)
            .collect();
        for (position, id) in ordered.iter().enumerate() {
            if !moved.contains(id) {
                continue;
            }
            let position = position as i64;
            sqlx::query!(
                "UPDATE channels SET position = ? WHERE id = ?",
                position,
                id
            )
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;

        let channels = self.list_channels().await?;
        Ok(ReorderOutcome { channels, moved })
    }
}
