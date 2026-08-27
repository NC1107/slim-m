// SPDX-License-Identifier: AGPL-3.0-only
//! `moderation_audit_log`: one row per removal, restore, timeout and lift,
//! written in the same transaction as the state change it records.
//!
//! `space_removals` and `member_timeouts` hold one row per member and answer
//! only "is this in force right now" - a restore deletes the removal it
//! reverses, and a re-issued timeout overwrites the one it replaces. This
//! table is where the acts themselves accumulate, so that neither of those
//! tables has to grow a soft-delete every in-force query would then have to
//! learn to skip. See the migration's own comment for that reasoning.
//!
//! `/reports/history` (`store/moderation_history.rs`) reads it over HTTP,
//! merged with resolved reports into one feed.

use crate::ids::UserId;

/// One moderation act, as it is written down.
///
/// `until` is the deadline the act concerns: the new one for a `timeout`, the
/// one cut short for a `timeout_cleared`, and absent for a removal or restore.
pub(super) struct ModerationAudit<'a> {
    pub(super) actor_id: UserId,
    pub(super) subject_id: UserId,
    pub(super) action: &'a str,
    pub(super) reason: Option<&'a str>,
    pub(super) until: Option<i64>,
    pub(super) created_at: i64,
}

/// Appends one audit row.
///
/// Takes a connection rather than the transaction itself so a caller can pass
/// `&mut *tx` and have the audit commit or roll back with the act it records;
/// a moderation change that lands without its trail, or a trail without its
/// change, is worse than either failing.
pub(super) async fn record_moderation_audit(
    conn: &mut sqlx::SqliteConnection,
    entry: ModerationAudit<'_>,
) -> Result<(), sqlx::Error> {
    sqlx::query!(
        r#"INSERT INTO moderation_audit_log
               (actor_id, subject_id, action, reason, until, created_at)
           VALUES (?, ?, ?, ?, ?, ?)"#,
        entry.actor_id,
        entry.subject_id,
        entry.action,
        entry.reason,
        entry.until,
        entry.created_at
    )
    .execute(&mut *conn)
    .await?;
    Ok(())
}
