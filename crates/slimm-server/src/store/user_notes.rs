// SPDX-License-Identifier: AGPL-3.0-only
//! A caller's own private note about another account.
//!
//! Modeled on `store/safety.rs`'s blocking relation: one row per (author,
//! subject) pair, WITHOUT ROWID, and read or written only through the
//! author's own id (see migration 0055). Unlike a block this has no second
//! direction anyone ever queries and no moderation surface at all - a note
//! is visible only to the author who wrote it, always.
//!
//! Purged with the author's account deletion in
//! [`super::account_deletion`], not the subject's: the note is the author's
//! data, so it leaves with them, and it must survive the subject being
//! renamed or deleted since it keys on id rather than username. The HTTP
//! layer (`http/user_notes.rs`) is what masks a note about a subject who no
//! longer exists or has been anonymized to look identical to one about a
//! subject who never existed; this module answers only "what did this
//! author store", with no opinion on whether the subject is still visible.

use super::{Store, now_ms};
use crate::ids::UserId;

/// A caller's private note about another account.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserNote {
    pub body: String,
    pub created_at: i64,
    pub updated_at: i64,
}

impl Store {
    /// The caller's own note about `subject`, or `None` if they have not left
    /// one. Caller-scoped by construction: the query is keyed on `author`, so
    /// there is no way to ask for anyone else's note through this function.
    pub async fn user_note(
        &self,
        author: UserId,
        subject: UserId,
    ) -> anyhow::Result<Option<UserNote>> {
        let row = sqlx::query!(
            r#"SELECT body AS "body!", created_at AS "created_at!",
                      updated_at AS "updated_at!"
               FROM user_notes WHERE author_id = ? AND subject_id = ?"#,
            author,
            subject
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(|r| UserNote {
            body: r.body,
            created_at: r.created_at,
            updated_at: r.updated_at,
        }))
    }

    /// Sets or clears the caller's note about `subject`. `None` deletes the
    /// row rather than storing a blank note, the same "empty clears it"
    /// convention `Store::update_me`'s status text already follows.
    ///
    /// The upsert is one statement with `RETURNING`, so a second write racing
    /// this one cannot land between an update and a re-read: whichever commits
    /// last is what both callers see next, and `created_at` is only ever set
    /// by the first insert, preserved by every update after it.
    pub async fn set_user_note(
        &self,
        author: UserId,
        subject: UserId,
        body: Option<&str>,
    ) -> anyhow::Result<Option<UserNote>> {
        let Some(body) = body else {
            sqlx::query!(
                "DELETE FROM user_notes WHERE author_id = ? AND subject_id = ?",
                author,
                subject
            )
            .execute(&self.pool)
            .await?;
            return Ok(None);
        };

        let now = now_ms();
        let row = sqlx::query!(
            r#"INSERT INTO user_notes (author_id, subject_id, body, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT (author_id, subject_id)
               DO UPDATE SET body = excluded.body, updated_at = excluded.updated_at
               RETURNING body AS "body!", created_at AS "created_at!",
                         updated_at AS "updated_at!""#,
            author,
            subject,
            body,
            now,
            now
        )
        .fetch_one(&self.pool)
        .await?;
        Ok(Some(UserNote {
            body: row.body,
            created_at: row.created_at,
            updated_at: row.updated_at,
        }))
    }
}
