// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Lookups by username and password hash: what login, the operator commands
//! and the re-authentication routes need to find an account and check it.

use super::Store;
use crate::ids::UserId;

impl Store {
    /// Looks up the user id and stored password hash for a live username, for the
    /// login path. `None` covers both no-such-user and a passwordless account.
    pub async fn find_credentials(
        &self,
        username: &str,
    ) -> anyhow::Result<Option<(UserId, String)>> {
        let row = sqlx::query!(
            r#"SELECT id AS "id!: UserId", password_hash
               FROM users
               WHERE username = ? AND deleted_at IS NULL"#,
            username
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.and_then(|r| r.password_hash.map(|hash| (r.id, hash))))
    }

    /// The id of the live account with this username, compared the way login
    /// does. For the operator commands, which name a member rather than sign in.
    pub async fn live_user_id_by_username(&self, username: &str) -> anyhow::Result<Option<UserId>> {
        let id = sqlx::query_scalar!(
            r#"SELECT id AS "id!: UserId" FROM users
               WHERE lower(username) = lower(?) AND deleted_at IS NULL"#,
            username
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(id)
    }

    /// The stored password hash for a live account, for proving the caller
    /// still holds the password before a security-sensitive change. `None` for a
    /// bot or a tombstoned account.
    pub async fn password_hash_for(&self, user_id: UserId) -> anyhow::Result<Option<String>> {
        let hash = sqlx::query_scalar!(
            "SELECT password_hash FROM users WHERE id = ? AND deleted_at IS NULL",
            user_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(hash.flatten())
    }
}
