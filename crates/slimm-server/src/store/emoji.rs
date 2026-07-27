// SPDX-License-Identifier: AGPL-3.0-only
//! Custom emoji persistence: the deployment's named images.
//!
//! The bytes are not stored here. An emoji points at an `attachments` row by
//! sha256 and reuses that table's on-disk blob, so an image uploaded twice, or
//! one whose bytes already exist because someone attached them to a message,
//! costs one copy. See `migrations/0016_custom_emoji.sql` for why the name and
//! its uniqueness are the only things this table adds.

use super::{Store, now_ms};
use crate::ids::{EmojiId, UserId};

/// Most emoji one deployment may hold. Every client lists all of them to
/// render `:shortcode:` at all, so this bounds a response nothing paginates.
pub const MAX_CUSTOM_EMOJI: i64 = 500;

/// One custom emoji as a client needs it: the name it is typed by and the id
/// its image is fetched at.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CustomEmoji {
    pub id: String,
    pub name: String,
    /// Hex sha256, the same id an attachment's bytes are fetched by.
    pub sha256: String,
    /// Null once the uploader's account has been deleted.
    pub uploader_id: Option<String>,
    pub created_at: i64,
}

/// Why an upload was refused.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CreateEmojiError {
    /// Another emoji already answers to this name.
    NameTaken,
    /// The deployment is at [`MAX_CUSTOM_EMOJI`].
    Full,
}

impl Store {
    /// Every custom emoji, oldest first. Unpaginated on purpose: a client
    /// needs the whole set to render any message, and the set is capped.
    pub async fn list_custom_emoji(&self) -> anyhow::Result<Vec<CustomEmoji>> {
        let rows = sqlx::query!(
            r#"SELECT id AS "id!: EmojiId", name AS "name!",
                      sha256 AS "sha256!", uploader_id AS "uploader_id?: UserId",
                      created_at AS "created_at!"
               FROM custom_emoji
               ORDER BY created_at ASC, rowid ASC"#
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| CustomEmoji {
                id: row.id.to_string(),
                name: row.name,
                sha256: hex_of(&row.sha256),
                uploader_id: row.uploader_id.map(|id| id.to_string()),
                created_at: row.created_at,
            })
            .collect())
    }

    /// Records an emoji against already-written bytes.
    ///
    /// Write-locked and counted inside the same transaction as the insert:
    /// the cap is only a cap if two concurrent uploads cannot both read a
    /// count below it and then both write.
    pub async fn create_custom_emoji(
        &self,
        id: EmojiId,
        name: &str,
        sha256: &[u8],
        uploader: UserId,
    ) -> anyhow::Result<Result<CustomEmoji, CreateEmojiError>> {
        let mut tx = self.begin_write().await?;
        let now = now_ms();
        let count = sqlx::query_scalar!("SELECT COUNT(*) FROM custom_emoji")
            .fetch_one(&mut *tx)
            .await?;
        if count as i64 >= MAX_CUSTOM_EMOJI {
            return Ok(Err(CreateEmojiError::Full));
        }

        let taken = sqlx::query_scalar!("SELECT COUNT(*) FROM custom_emoji WHERE name = ?", name)
            .fetch_one(&mut *tx)
            .await?;
        if taken > 0 {
            return Ok(Err(CreateEmojiError::NameTaken));
        }

        sqlx::query!(
            "INSERT INTO custom_emoji (id, name, sha256, uploader_id, created_at)
             VALUES (?, ?, ?, ?, ?)",
            id,
            name,
            sha256,
            uploader,
            now
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;

        Ok(Ok(CustomEmoji {
            id: id.to_string(),
            name: name.to_owned(),
            sha256: hex_of(sha256),
            uploader_id: Some(uploader.to_string()),
            created_at: now,
        }))
    }

    /// The bytes an emoji points at, or None if no such emoji exists.
    pub async fn custom_emoji_sha256(&self, id: EmojiId) -> anyhow::Result<Option<Vec<u8>>> {
        let row = sqlx::query!(
            r#"SELECT sha256 AS "sha256!" FROM custom_emoji WHERE id = ?"#,
            id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|row| row.sha256))
    }

    /// Removes an emoji. Returns whether it existed, so a repeated delete is
    /// idempotent rather than an error.
    ///
    /// The bytes are left behind deliberately: another emoji or a message may
    /// reference the same hash, and the orphan sweep is what reclaims a hash
    /// nothing points at any more.
    pub async fn delete_custom_emoji(&self, id: EmojiId) -> anyhow::Result<bool> {
        let result = sqlx::query!("DELETE FROM custom_emoji WHERE id = ?", id)
            .execute(&self.pool)
            .await?;
        Ok(result.rows_affected() > 0)
    }
}

fn hex_of(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}
