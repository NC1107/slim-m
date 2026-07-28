// SPDX-License-Identifier: AGPL-3.0-only
//! Deployment-wide settings an admin changes at runtime.
//!
//! One row, read on registration and written from the Space settings screen.
//! See `migrations/0018_space_settings.sql` for why the default is `invite`.

use anyhow::Context;
use sqlx::SqliteExecutor;

use super::Store;
use super::now_ms;

/// Who may create an account on this deployment.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JoinPolicy {
    /// A valid invite code is required. The default, and what every
    /// deployment that predates this setting keeps on upgrade.
    Invite,
    /// Anyone who can reach the server may register.
    Open,
}

impl JoinPolicy {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Invite => "invite",
            Self::Open => "open",
        }
    }

    /// Unrecognised text reads as [`JoinPolicy::Invite`] rather than as open.
    /// The CHECK constraint makes that unreachable through this API, and the
    /// fallback still has to be the closed one: a row somehow holding junk
    /// must not be the reason a Space is open to the internet.
    ///
    /// Deliberately not [`std::str::FromStr`]: that returns a `Result`, and
    /// this must not have a failing branch a caller could unwrap into a panic.
    pub fn parse(value: &str) -> Self {
        match value {
            "open" => Self::Open,
            _ => Self::Invite,
        }
    }
}

/// Read inside a caller's transaction, so registration sees a policy change
/// that lands concurrently rather than a snapshot from before it.
pub(super) async fn read_join_policy<'e, E>(executor: E) -> anyhow::Result<JoinPolicy>
where
    E: SqliteExecutor<'e>,
{
    let row = sqlx::query_scalar!(
        r#"SELECT join_policy AS "p!: String" FROM space_settings WHERE id = 1"#
    )
    .fetch_optional(executor)
    .await
    .context("read join policy")?;
    Ok(row
        .as_deref()
        .map(JoinPolicy::parse)
        .unwrap_or(JoinPolicy::Invite))
}

impl Store {
    pub async fn join_policy(&self) -> anyhow::Result<JoinPolicy> {
        read_join_policy(&self.pool).await
    }

    pub async fn set_join_policy(&self, policy: JoinPolicy) -> anyhow::Result<()> {
        let now = now_ms();
        let value = policy.as_str();
        sqlx::query!(
            "UPDATE space_settings SET join_policy = ?, updated_at = ? WHERE id = 1",
            value,
            now
        )
        .execute(&self.pool)
        .await
        .context("set join policy")?;
        Ok(())
    }
}
