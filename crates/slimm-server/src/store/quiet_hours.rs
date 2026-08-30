// SPDX-License-Identifier: AGPL-3.0-only
//! Persistence for the account-wide quiet-hours window (migration 0056):
//! an optional time-of-day span, in minutes since midnight UTC, during
//! which `push::recipients::narrow_for_notification_preference` treats an
//! `everything` preference as `mentions`.
//!
//! Read singly by `GET /push/quiet-hours` for the caller's own settings
//! screen, and in batch by push fan-out
//! (`push::recipients::narrow_for_notification_preference`), the same split
//! `store/notifications.rs` already uses between its single and batched
//! reads.

use std::collections::HashMap;

use sqlx::QueryBuilder;

use super::Store;
use crate::ids::UserId;
use crate::notifications::QuietHours;

impl Store {
    /// The caller's own quiet-hours window, or `None` when disabled or the
    /// account is gone - the two collapse here because every caller of this
    /// function has already confirmed the account exists through a sibling
    /// read in the same request (`GET /push/quiet-hours` reads
    /// [`Store::notification_preference`] first), so a second "does this
    /// account exist" answer is not needed.
    pub async fn quiet_hours(&self, user_id: UserId) -> anyhow::Result<Option<QuietHours>> {
        let row = sqlx::query!(
            r#"SELECT quiet_hours_start_minute AS "start: i64", quiet_hours_end_minute AS "end: i64"
               FROM users WHERE id = ? AND deleted_at IS NULL"#,
            user_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.and_then(|r| match (r.start, r.end) {
            (Some(start), Some(end)) => QuietHours::parse(start, end),
            _ => None,
        }))
    }

    /// Sets or clears the caller's quiet-hours window. Returns `false` if
    /// the account is gone, the same tiny concurrent-deletion window
    /// documented on [`Store::update_display_name`](super::Store::update_display_name).
    pub async fn set_quiet_hours(
        &self,
        user_id: UserId,
        quiet_hours: Option<QuietHours>,
    ) -> anyhow::Result<bool> {
        let (start, end) = match quiet_hours {
            Some(window) => (
                Some(i64::from(window.start_minute)),
                Some(i64::from(window.end_minute)),
            ),
            None => (None, None),
        };
        let affected = sqlx::query!(
            "UPDATE users SET quiet_hours_start_minute = ?, quiet_hours_end_minute = ?
             WHERE id = ? AND deleted_at IS NULL",
            start,
            end,
            user_id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        Ok(affected > 0)
    }

    /// Batched read for push fan-out: one query for however many recipients
    /// survived the notification-preference narrowing, the
    /// [`Store::notification_preferences`] shape rather than one lookup per
    /// candidate. An id absent from the map means either the account is
    /// gone or quiet hours are disabled - both read as "not in a quiet
    /// window" at the call site, since neither should narrow a push.
    pub async fn quiet_hours_for_users(
        &self,
        user_ids: &[UserId],
    ) -> anyhow::Result<HashMap<UserId, QuietHours>> {
        if user_ids.is_empty() {
            return Ok(HashMap::new());
        }

        // Built, not a fixed `query!`: the id list is variable length; see `user_profiles`.
        let mut builder = QueryBuilder::new(
            "SELECT id, quiet_hours_start_minute, quiet_hours_end_minute FROM users \
             WHERE deleted_at IS NULL AND id IN (",
        );
        let mut separated = builder.separated(", ");
        for id in user_ids {
            separated.push_bind(*id);
        }
        builder.push(")");

        let rows = builder.build().fetch_all(&self.pool).await?;
        use sqlx::Row;
        let mut windows = HashMap::new();
        for row in rows {
            let id: UserId = row.try_get("id")?;
            let start: Option<i64> = row.try_get("quiet_hours_start_minute")?;
            let end: Option<i64> = row.try_get("quiet_hours_end_minute")?;
            if let (Some(start), Some(end)) = (start, end)
                && let Some(window) = QuietHours::parse(start, end)
            {
                windows.insert(id, window);
            }
        }
        Ok(windows)
    }
}
