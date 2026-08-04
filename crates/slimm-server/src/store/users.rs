// SPDX-License-Identifier: AGPL-3.0-only
//! User profile persistence: public profile reads, the caller's own
//! display-name update, and the member list.
//!
//! Every read here filters `deleted_at IS NULL`, so a deleted or anonymized
//! account answers exactly like an id that was never used: existence must not
//! be observable here any more than it is for a channel or a message.

use sqlx::QueryBuilder;
use uuid::Uuid;

use super::{Store, User};
use crate::ids::UserId;

impl Store {
    /// A user's public profile: id, username, display name, and creation
    /// time. Nothing from the auth tables (password hash, sessions, tokens)
    /// is reachable through this path.
    ///
    /// A deleted or anonymized account answers `None`, the same as an id
    /// that was never used, so this cannot confirm someone deleted their
    /// account.
    pub async fn user_profile(&self, id: UserId) -> anyhow::Result<Option<User>> {
        let row = sqlx::query!(
            r#"SELECT id AS "id!: UserId", username AS "username!",
                      display_name AS "display_name!", created_at AS "created_at!",
                      avatar_updated_at
               FROM users WHERE id = ? AND deleted_at IS NULL"#,
            id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| User {
            id: r.id,
            username: r.username,
            display_name: r.display_name,
            created_at: r.created_at,
            avatar_updated_at: r.avatar_updated_at,
        }))
    }

    /// Public profiles for a batch of ids, in one query. An id with nothing
    /// live to report (never existed, or deleted) is simply absent from the
    /// result; the caller must treat a missing id that way rather than
    /// expecting one entry per input, the same contract
    /// [`Store::reactions_for_messages`] has for a message with no reactions.
    pub async fn user_profiles(&self, ids: &[UserId]) -> anyhow::Result<Vec<User>> {
        if ids.is_empty() {
            return Ok(Vec::new());
        }

        // Built rather than a fixed `query!` because the id list is variable
        // length and SQLite has no array binding.
        let mut builder = QueryBuilder::new(
            "SELECT id, username, display_name, created_at, avatar_updated_at FROM users \
             WHERE deleted_at IS NULL AND id IN (",
        );
        let mut separated = builder.separated(", ");
        for id in ids {
            separated.push_bind(*id);
        }
        builder.push(")");

        let rows = builder.build().fetch_all(&self.pool).await?;

        use sqlx::Row;
        let mut users = Vec::with_capacity(rows.len());
        for row in rows {
            users.push(User {
                id: row.try_get("id")?,
                username: row.try_get("username")?,
                display_name: row.try_get("display_name")?,
                created_at: row.try_get("created_at")?,
                avatar_updated_at: row.try_get("avatar_updated_at")?,
            });
        }
        Ok(users)
    }

    /// The live ids behind a batch of usernames, exact case-sensitive match
    /// (the same comparison a login already makes), for resolving a message's
    /// `@name` mentions to accounts. A name with nobody live behind it -
    /// never registered, or deleted - is simply absent, the same contract
    /// [`Store::user_profiles`] has for an id.
    pub async fn user_ids_for_usernames(
        &self,
        usernames: &[String],
    ) -> anyhow::Result<Vec<UserId>> {
        if usernames.is_empty() {
            return Ok(Vec::new());
        }

        let mut builder =
            QueryBuilder::new("SELECT id FROM users WHERE deleted_at IS NULL AND username IN (");
        let mut separated = builder.separated(", ");
        for name in usernames {
            separated.push_bind(name);
        }
        builder.push(")");

        let ids: Vec<UserId> = builder.build_query_scalar().fetch_all(&self.pool).await?;
        Ok(ids)
    }

    /// Updates the caller's own display name. Username is not updatable
    /// here: it backs the live per-account uniqueness index
    /// (`users_username_live`), and changing it needs a dedicated flow that
    /// can handle the resulting collision, not a field silently accepted (or
    /// silently ignored) on this endpoint.
    ///
    /// Returns `None` if the account is gone: the same tiny window
    /// documented on [`Store::delete_account`], where a write already in
    /// flight on a token that was still valid when the request started can
    /// land just after a concurrent deletion.
    pub async fn update_display_name(
        &self,
        user_id: UserId,
        display_name: &str,
    ) -> anyhow::Result<Option<User>> {
        let affected = sqlx::query!(
            "UPDATE users SET display_name = ? WHERE id = ? AND deleted_at IS NULL",
            display_name,
            user_id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if affected == 0 {
            return Ok(None);
        }
        self.user_profile(user_id).await
    }

    /// How many live accounts this deployment has. Used to show a
    /// prospective joiner, via an invite's metadata, roughly how big the
    /// community is before they sign up; a deleted or anonymized account
    /// does not count, and neither does a removed one, any more than either
    /// appears in [`Store::list_members`] or is counted by
    /// [`super::roles::administrator_count`].
    pub async fn member_count(&self) -> anyhow::Result<i64> {
        let count = sqlx::query_scalar!(
            r#"SELECT COUNT(*) AS "count!: i64" FROM users
               WHERE deleted_at IS NULL
               AND NOT EXISTS (SELECT 1 FROM space_removals sr WHERE sr.user_id = users.id)"#
        )
        .fetch_one(&self.pool)
        .await?;
        Ok(count)
    }

    /// The deployment's live members, oldest first, keyset-paginated by id.
    /// UUIDv7 sorts chronologically, so id order is already creation order
    /// and no separate cursor column is needed.
    pub async fn list_members(
        &self,
        after: Option<UserId>,
        limit: i64,
    ) -> anyhow::Result<Vec<User>> {
        let after = after.unwrap_or(UserId(Uuid::nil()));
        let rows = sqlx::query!(
            r#"SELECT id AS "id!: UserId", username AS "username!",
                      display_name AS "display_name!", created_at AS "created_at!",
                      avatar_updated_at
               FROM users WHERE deleted_at IS NULL AND id > ?
               AND NOT EXISTS (SELECT 1 FROM space_removals sr WHERE sr.user_id = users.id)
               ORDER BY id ASC LIMIT ?"#,
            after,
            limit
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| User {
                id: r.id,
                username: r.username,
                display_name: r.display_name,
                created_at: r.created_at,
                avatar_updated_at: r.avatar_updated_at,
            })
            .collect())
    }

    /// Marks the caller's avatar as freshly set, stamping `avatar_updated_at`
    /// with now. Called after the bytes are already written to disk (see
    /// `Media::write_avatar`), never before: the file-then-row ordering means
    /// a crash between the two steps leaves the old avatar's timestamp
    /// pointing at bytes that were just overwritten, not a row that promises
    /// an avatar no file backs.
    ///
    /// Returns `None` if the account is gone, the same tiny race documented
    /// on [`Store::update_display_name`].
    pub async fn set_avatar_updated(&self, user_id: UserId) -> anyhow::Result<Option<User>> {
        let now = super::now_ms();
        let affected = sqlx::query!(
            "UPDATE users SET avatar_updated_at = ? WHERE id = ? AND deleted_at IS NULL",
            now,
            user_id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if affected == 0 {
            return Ok(None);
        }
        self.user_profile(user_id).await
    }

    /// Clears the caller's avatar. The file itself is removed by the caller
    /// (`Media::delete_avatar`) after this succeeds.
    pub async fn clear_avatar(&self, user_id: UserId) -> anyhow::Result<Option<User>> {
        let affected = sqlx::query!(
            "UPDATE users SET avatar_updated_at = NULL WHERE id = ? AND deleted_at IS NULL",
            user_id
        )
        .execute(&self.pool)
        .await?
        .rows_affected();
        if affected == 0 {
            return Ok(None);
        }
        self.user_profile(user_id).await
    }
}
