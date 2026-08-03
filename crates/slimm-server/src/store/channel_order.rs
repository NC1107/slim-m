// SPDX-License-Identifier: AGPL-3.0-only
//! Setting the deployment's channel order and category placement in one
//! caller-supplied, category-grouped list, applied atomically - so a drag
//! between two rail sections reassigns and repositions in one request rather
//! than a move followed by a reorder that could half-apply. See
//! docs/decisions/0006-channel-categories.md.

use std::collections::{HashMap, HashSet};

use super::{Channel, Store};
use crate::ids::{ChannelCategoryId, ChannelId};

/// One rail section's ordered contents, as submitted by a drag: the category
/// it names (`None` for the implicit uncategorised section) and every
/// channel now filed under it, in display order.
#[derive(Debug, Clone)]
pub struct ChannelOrderGroup {
    pub category_id: Option<ChannelCategoryId>,
    pub channel_ids: Vec<ChannelId>,
}

/// Why setting the channel order failed.
#[derive(Debug)]
pub enum ReorderChannelsError {
    /// The channel ids named across every group did not add up to exactly
    /// the live, non-DM, non-thread channels: some were repeated, some live
    /// channels were left out, or some named ids are not live channels at
    /// all. `missing` and `extra` are each empty unless that half of the
    /// mismatch applies.
    Mismatch {
        missing: Vec<ChannelId>,
        extra: Vec<ChannelId>,
    },
    /// A group named a category id that is not a live category.
    UnknownCategory(Vec<ChannelCategoryId>),
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
    /// Which channels actually changed category or position. A caller
    /// submitting the arrangement it already has gets an empty list rather
    /// than one claiming every channel moved - mirrors `edit_message`
    /// declining to mint a change nobody made.
    pub moved: Vec<ChannelId>,
}

impl Store {
    /// Sets the deployment's channel order and category placement to exactly
    /// `groups`: position `i` and `group.category_id` for the channel at
    /// index `i` of `group.channel_ids`. Refuses a set of groups whose
    /// channel ids, flattened, are not exactly the live, non-DM, non-thread
    /// channels - too few would leave a gap nothing else fills, too many or a
    /// repeat names something this route cannot place - so a caller always
    /// knows whether its drag actually took effect. Also refuses a group
    /// naming a category id that is not a live category, before writing
    /// anything.
    ///
    /// One transaction from the first read (see [`Store::begin_write`]), so a
    /// concurrent create, delete, or category delete cannot land between the
    /// validation and the write and silently invalidate it.
    pub async fn reorder_channels(
        &self,
        groups: &[ChannelOrderGroup],
    ) -> Result<ReorderOutcome, ReorderChannelsError> {
        let mut tx = self.begin_write().await?;

        let live: Vec<(ChannelId, Option<ChannelCategoryId>, i64)> = sqlx::query!(
            r#"SELECT id AS "id!: ChannelId",
                      category_id AS "category_id: ChannelCategoryId",
                      position AS "position!: i64"
               FROM channels
               WHERE deleted_at IS NULL AND kind != 'dm' AND parent_message_id IS NULL"#
        )
        .fetch_all(&mut *tx)
        .await?
        .into_iter()
        .map(|r| (r.id, r.category_id, r.position))
        .collect();

        let ordered: Vec<ChannelId> = groups
            .iter()
            .flat_map(|group| group.channel_ids.iter().copied())
            .collect();
        let live_set: HashSet<ChannelId> = live.iter().map(|(id, ..)| *id).collect();
        let given_set: HashSet<ChannelId> = ordered.iter().copied().collect();
        if given_set.len() != ordered.len() || live_set != given_set {
            return Err(ReorderChannelsError::Mismatch {
                missing: live_set.difference(&given_set).copied().collect(),
                extra: given_set.difference(&live_set).copied().collect(),
            });
        }

        let named_categories: HashSet<ChannelCategoryId> = groups
            .iter()
            .filter_map(|group| group.category_id)
            .collect();
        if !named_categories.is_empty() {
            let live_categories: HashSet<ChannelCategoryId> = sqlx::query_scalar!(
                r#"SELECT id AS "id!: ChannelCategoryId" FROM channel_categories
                   WHERE deleted_at IS NULL"#
            )
            .fetch_all(&mut *tx)
            .await?
            .into_iter()
            .collect();
            let unknown: Vec<ChannelCategoryId> = named_categories
                .difference(&live_categories)
                .copied()
                .collect();
            if !unknown.is_empty() {
                return Err(ReorderChannelsError::UnknownCategory(unknown));
            }
        }

        let before: HashMap<ChannelId, (Option<ChannelCategoryId>, i64)> = live
            .into_iter()
            .map(|(id, category_id, position)| (id, (category_id, position)))
            .collect();

        let mut moved = Vec::new();
        for group in groups {
            for (position, id) in group.channel_ids.iter().enumerate() {
                let position = position as i64;
                let target = (group.category_id, position);
                if before.get(id) == Some(&target) {
                    continue;
                }
                moved.push(*id);
                sqlx::query!(
                    "UPDATE channels SET category_id = ?, position = ? WHERE id = ?",
                    group.category_id,
                    position,
                    id
                )
                .execute(&mut *tx)
                .await?;
            }
        }
        tx.commit().await?;

        let channels = self.list_channels().await?;
        Ok(ReorderOutcome { channels, moved })
    }
}
