// SPDX-License-Identifier: AGPL-3.0-only
//! Channel category persistence: create, rename, reposition, and soft-delete.
//!
//! A category is organisational only - it groups and orders channels of any
//! kind, and grants and denies nothing. See
//! docs/decisions/0006-channel-categories.md and docs/IMPLIED-GAPS.md.

use super::{ChannelCategory, Store, now_ms};
use crate::ids::ChannelCategoryId;

impl Store {
    /// Lists the deployment's live categories, in display order.
    pub async fn list_categories(&self) -> anyhow::Result<Vec<ChannelCategory>> {
        let rows = sqlx::query!(
            r#"SELECT id AS "id!: ChannelCategoryId", name AS "name!",
                      position AS "position!: i64", created_at AS "created_at!"
               FROM channel_categories
               WHERE deleted_at IS NULL
               ORDER BY position, created_at"#
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| ChannelCategory {
                id: r.id,
                name: r.name,
                position: r.position,
                created_at: r.created_at,
            })
            .collect())
    }

    /// Creates a category, appended after every live one - the same
    /// "read the live maximum inside this transaction" shape
    /// [`super::channels::Store::create_channel`] uses for a channel's own
    /// position, so two concurrent creates cannot both claim the last slot.
    pub async fn create_category(&self, name: &str) -> anyhow::Result<ChannelCategory> {
        let id = ChannelCategoryId::generate();
        let now = now_ms();
        let mut tx = self.begin_write().await?;
        let position = sqlx::query_scalar!(
            r#"SELECT COALESCE(MAX(position), -1) + 1 AS "next!: i64" FROM channel_categories
               WHERE deleted_at IS NULL"#
        )
        .fetch_one(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO channel_categories (id, name, position, created_at) VALUES (?, ?, ?, ?)",
            id,
            name,
            position,
            now
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(ChannelCategory {
            id,
            name: name.to_owned(),
            position,
            created_at: now,
        })
    }

    /// Renames and/or repositions a category. `None` for either leaves that
    /// field untouched, the same "at least one, absent means unchanged"
    /// convention [`super::channels::Store::update_channel`] follows.
    /// Returns `None` if the category does not exist or was deleted.
    pub async fn update_category(
        &self,
        id: ChannelCategoryId,
        name: Option<&str>,
        position: Option<i64>,
    ) -> anyhow::Result<Option<ChannelCategory>> {
        let affected = match (name, position) {
            (Some(name), Some(position)) => sqlx::query!(
                "UPDATE channel_categories SET name = ?, position = ? \
                 WHERE id = ? AND deleted_at IS NULL",
                name,
                position,
                id
            )
            .execute(&self.pool)
            .await?
            .rows_affected(),
            (Some(name), None) => sqlx::query!(
                "UPDATE channel_categories SET name = ? WHERE id = ? AND deleted_at IS NULL",
                name,
                id
            )
            .execute(&self.pool)
            .await?
            .rows_affected(),
            (None, Some(position)) => sqlx::query!(
                "UPDATE channel_categories SET position = ? WHERE id = ? AND deleted_at IS NULL",
                position,
                id
            )
            .execute(&self.pool)
            .await?
            .rows_affected(),
            (None, None) => {
                let exists = sqlx::query_scalar!(
                    r#"SELECT 1 AS "one!: i64" FROM channel_categories
                       WHERE id = ? AND deleted_at IS NULL"#,
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
        let row = sqlx::query!(
            r#"SELECT id AS "id!: ChannelCategoryId", name AS "name!",
                      position AS "position!: i64", created_at AS "created_at!"
               FROM channel_categories WHERE id = ? AND deleted_at IS NULL"#,
            id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| ChannelCategory {
            id: r.id,
            name: r.name,
            position: r.position,
            created_at: r.created_at,
        }))
    }

    /// Soft-deletes a category. Its channels are never deleted with it - they
    /// fall back to uncategorised in the same transaction, so a channel is
    /// never orphaned even for the instant between the two statements.
    /// Returns whether this call performed the delete, so a retry against an
    /// already-deleted category is idempotent rather than an error, the same
    /// convention [`super::channels::Store::delete_channel`] follows.
    pub async fn delete_category(&self, id: ChannelCategoryId) -> anyhow::Result<bool> {
        let now = now_ms();
        let mut tx = self.begin_write().await?;
        let affected = sqlx::query!(
            "UPDATE channel_categories SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL",
            now,
            id
        )
        .execute(&mut *tx)
        .await?
        .rows_affected();
        if affected > 0 {
            sqlx::query!(
                "UPDATE channels SET category_id = NULL WHERE category_id = ?",
                id
            )
            .execute(&mut *tx)
            .await?;
        }
        tx.commit().await?;
        Ok(affected > 0)
    }
}
