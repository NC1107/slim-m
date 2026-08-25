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

/// The effective per-channel canvas object cap, read inside a caller's
/// transaction so an enforcement count sees a cap change that lands
/// concurrently rather than a snapshot from before it - the same reasoning
/// [`read_join_policy`] gives. Falls back to `MAX_OBJECTS_PER_CHANNEL` for a
/// row written before this column existed.
pub(super) async fn read_canvas_object_cap<'e, E>(executor: E) -> anyhow::Result<i64>
where
    E: SqliteExecutor<'e>,
{
    let cap = sqlx::query_scalar!(
        r#"SELECT canvas_object_cap AS "c!: i64" FROM space_settings WHERE id = 1"#
    )
    .fetch_optional(executor)
    .await
    .context("read canvas object cap")?;
    Ok(cap.unwrap_or(super::MAX_OBJECTS_PER_CHANNEL))
}

impl Store {
    pub async fn join_policy(&self) -> anyhow::Result<JoinPolicy> {
        read_join_policy(&self.pool).await
    }

    /// The per-channel canvas object cap in force for this deployment.
    pub async fn canvas_object_cap(&self) -> anyhow::Result<i64> {
        read_canvas_object_cap(&self.pool).await
    }

    /// Sets the per-channel canvas object cap. The caller is responsible for
    /// range-checking against `MIN_CANVAS_OBJECT_CAP` and
    /// `MAX_CANVAS_OBJECT_CAP`; the DB CHECK only guards the `>= 1` invariant.
    pub async fn set_canvas_object_cap(&self, cap: i64) -> anyhow::Result<()> {
        let now = now_ms();
        sqlx::query!(
            "UPDATE space_settings SET canvas_object_cap = ?, updated_at = ? WHERE id = 1",
            cap,
            now
        )
        .execute(&self.pool)
        .await
        .context("set canvas object cap")?;
        Ok(())
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

#[cfg(test)]
mod tests {
    use super::JoinPolicy;

    /// The security-critical branch. The CHECK constraint makes junk
    /// unreachable through the write path, so this fallback is the only thing
    /// between a row that somehow holds garbage and a Space open to the
    /// internet: anything unrecognised must read closed, never Open.
    #[test]
    fn unrecognised_text_reads_as_invite_never_open() {
        for junk in ["", "OPEN", "Open", "public", "invite ", "open\n", "yes"] {
            assert_eq!(
                JoinPolicy::parse(junk),
                JoinPolicy::Invite,
                "{junk:?} must fail closed"
            );
        }
    }

    #[test]
    fn exactly_open_reads_as_open() {
        assert_eq!(JoinPolicy::parse("open"), JoinPolicy::Open);
        assert_eq!(JoinPolicy::parse("invite"), JoinPolicy::Invite);
    }

    /// The two halves cannot drift: whatever `as_str` writes, `parse` reads back.
    #[test]
    fn as_str_round_trips_through_parse() {
        for policy in [JoinPolicy::Invite, JoinPolicy::Open] {
            assert_eq!(JoinPolicy::parse(policy.as_str()), policy);
        }
    }
}
