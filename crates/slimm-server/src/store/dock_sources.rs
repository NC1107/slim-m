// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Extra Dock module sources (docs/decisions/0046-more-than-one-module-source.md).

use super::{Store, now_ms};

/// One community source an admin added beside the official one.
#[derive(Debug, Clone)]
pub struct DockSource {
    pub id: String,
    pub repo: String,
    pub created_at: i64,
}

impl Store {
    /// Adds a source, or returns the one already stored for that repo, so a
    /// retried add is not an error. `Ok((source, created))`.
    pub async fn add_dock_source(&self, repo: &str) -> anyhow::Result<(DockSource, bool)> {
        let id = uuid::Uuid::now_v7().to_string();
        let now = now_ms();
        let inserted = sqlx::query!(
            "INSERT INTO dock_sources (id, repo, created_at) VALUES (?, ?, ?)
             ON CONFLICT(repo) DO NOTHING",
            id,
            repo,
            now
        )
        .execute(&self.pool)
        .await?
        .rows_affected()
            > 0;
        let source = sqlx::query_as!(
            DockSource,
            r#"SELECT id AS "id!", repo AS "repo!", created_at AS "created_at!"
               FROM dock_sources WHERE repo = ?"#,
            repo
        )
        .fetch_one(&self.pool)
        .await?;
        Ok((source, inserted))
    }

    /// Every added source, oldest first: that order is the tie-break when two
    /// community sources publish the same module id.
    pub async fn list_dock_sources(&self) -> anyhow::Result<Vec<DockSource>> {
        Ok(sqlx::query_as!(
            DockSource,
            r#"SELECT id AS "id!", repo AS "repo!", created_at AS "created_at!"
               FROM dock_sources ORDER BY created_at, id"#
        )
        .fetch_all(&self.pool)
        .await?)
    }

    pub async fn dock_source(&self, id: &str) -> anyhow::Result<Option<DockSource>> {
        Ok(sqlx::query_as!(
            DockSource,
            r#"SELECT id AS "id!", repo AS "repo!", created_at AS "created_at!"
               FROM dock_sources WHERE id = ?"#,
            id
        )
        .fetch_optional(&self.pool)
        .await?)
    }

    /// Removes a source. Its installed modules are left alone. `Ok(false)` if
    /// it did not exist.
    pub async fn remove_dock_source(&self, id: &str) -> anyhow::Result<bool> {
        let affected = sqlx::query!("DELETE FROM dock_sources WHERE id = ?", id)
            .execute(&self.pool)
            .await?
            .rows_affected();
        Ok(affected > 0)
    }
}
