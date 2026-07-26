// SPDX-License-Identifier: AGPL-3.0-only
//! Persistence for the one durable piece of presence: a user's chosen
//! visibility. Everything else about presence (whether they are actually
//! connected right now) is in-memory only; see [`crate::presence`].

use super::Store;
use crate::ids::UserId;
use crate::presence::Visibility;

impl Store {
    /// The visibility a live user has chosen, or `None` if the account is
    /// gone (deleted or never existed) -- the same "answers like an id that
    /// was never used" contract every other profile read in this crate
    /// follows.
    ///
    /// An unparseable stored value defaults to `Online` rather than failing
    /// the request: this column is only ever written through
    /// [`Store::set_presence_visibility`], which only accepts
    /// [`Visibility::as_str`] spellings, so this should not happen, and
    /// presence is not worth an internal error over.
    pub async fn presence_visibility(&self, user_id: UserId) -> anyhow::Result<Option<Visibility>> {
        let row = sqlx::query!(
            r#"SELECT presence_visibility AS "presence_visibility!" FROM users
               WHERE id = ? AND deleted_at IS NULL"#,
            user_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| Visibility::parse(&r.presence_visibility).unwrap_or_default()))
    }

    /// Sets the caller's visibility preference. Returns `false` if the
    /// account is gone, the same tiny concurrent-deletion window documented
    /// on [`Store::update_display_name`](super::Store::update_display_name).
    pub async fn set_presence_visibility(
        &self,
        user_id: UserId,
        visibility: Visibility,
    ) -> anyhow::Result<bool> {
        let value = visibility.as_str();
        let affected = sqlx::query!(
            "UPDATE users SET presence_visibility = ? WHERE id = ? AND deleted_at IS NULL",
            value,
            user_id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        Ok(affected > 0)
    }
}
