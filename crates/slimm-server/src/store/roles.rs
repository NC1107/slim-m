// SPDX-License-Identifier: AGPL-3.0-only
//! Role CRUD and member role assignment.
//!
//! Two authorization concerns sit above this module, in `http::roles`,
//! because they need the caller's own identity: a role's permissions, on
//! create, on update, and again on every assignment, must never include a bit
//! the caller does not themselves hold, or granting a role becomes a way to
//! hand out access nobody actually approved. What lives here instead is the
//! invariant only this module can see across every caller: the deployment
//! must always keep at least one administrator, since losing the last one has
//! no recovery path short of direct database surgery. Every mutation that
//! could remove someone's last route to ADMINISTRATOR checks that inside the
//! same transaction as the write, and rolls back rather than commit a state
//! with zero administrators.

use sqlx::{QueryBuilder, SqliteConnection};

use super::Store;
use crate::ids::{RoleId, UserId};
use crate::permissions::Permissions;

/// A role: a named, reusable permission set members can hold.
#[derive(Debug, Clone)]
pub struct Role {
    pub id: RoleId,
    pub name: String,
    pub permissions: Permissions,
    pub is_everyone: bool,
    pub created_at: i64,
}

/// Why a role mutation was refused.
#[derive(Debug)]
pub enum RoleGuardError {
    /// `@everyone` is the base of every permission evaluation, and the
    /// partial unique index on `is_everyone` already guarantees there is
    /// exactly one; deleting it would leave the evaluator with no base.
    IsEveryone,
    /// This change would leave the deployment with no administrator.
    LastAdministrator,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for RoleGuardError {
    fn from(err: sqlx::Error) -> Self {
        RoleGuardError::Internal(err.into())
    }
}

impl From<anyhow::Error> for RoleGuardError {
    fn from(err: anyhow::Error) -> Self {
        RoleGuardError::Internal(err)
    }
}

impl Store {
    /// Every role, highest position first.
    pub async fn list_roles(&self) -> anyhow::Result<Vec<Role>> {
        let rows = sqlx::query_as!(
            Role,
            r#"SELECT id AS "id!: RoleId", name AS "name!",
                      permissions AS "permissions!: Permissions",
                      is_everyone AS "is_everyone!: bool", created_at AS "created_at!"
               FROM roles ORDER BY position DESC, created_at"#
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows)
    }

    /// Fetches one role by id.
    pub async fn role(&self, role_id: RoleId) -> anyhow::Result<Option<Role>> {
        let row = sqlx::query_as!(
            Role,
            r#"SELECT id AS "id!: RoleId", name AS "name!",
                      permissions AS "permissions!: Permissions",
                      is_everyone AS "is_everyone!: bool", created_at AS "created_at!"
               FROM roles WHERE id = ?"#,
            role_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row)
    }

    /// Updates a role's name and/or permissions; `None` for a field leaves it
    /// unchanged. `Ok(None)` if the role does not exist.
    ///
    /// Whether the requested permissions are something the caller may grant
    /// is checked by `http::roles` before this runs, since that needs the
    /// caller's own effective permissions; this only guards the structural
    /// invariant, rolling back if the update would leave the deployment with
    /// no administrator.
    ///
    /// That guard runs whenever permissions were touched at all, rather than
    /// trying to detect whether the ADMINISTRATOR bit specifically moved. Only
    /// a permissions change can remove an administrator, and checking the
    /// broader condition stays correct even when the bit arrives folded into a
    /// larger change.
    pub async fn update_role(
        &self,
        role_id: RoleId,
        name: Option<&str>,
        permissions: Option<Permissions>,
    ) -> Result<Option<Role>, RoleGuardError> {
        let mut tx = self.pool.begin().await?;

        let affected: u64 = match (name, permissions) {
            (Some(name), Some(perms)) => {
                let bits = perms.bits();
                sqlx::query!(
                    "UPDATE roles SET name = ?, permissions = ? WHERE id = ?",
                    name,
                    bits,
                    role_id
                )
                .execute(&mut *tx)
                .await?
                .rows_affected()
            }
            (Some(name), None) => {
                sqlx::query!("UPDATE roles SET name = ? WHERE id = ?", name, role_id)
                    .execute(&mut *tx)
                    .await?
                    .rows_affected()
            }
            (None, Some(perms)) => {
                let bits = perms.bits();
                sqlx::query!(
                    "UPDATE roles SET permissions = ? WHERE id = ?",
                    bits,
                    role_id
                )
                .execute(&mut *tx)
                .await?
                .rows_affected()
            }
            (None, None) => {
                let exists = sqlx::query_scalar!(
                    r#"SELECT 1 AS "one!: i64" FROM roles WHERE id = ?"#,
                    role_id
                )
                .fetch_optional(&mut *tx)
                .await?;
                u64::from(exists.is_some())
            }
        };
        if affected == 0 {
            return Ok(None);
        }

        // Guarded on any permissions change; see the note on this function.
        if permissions.is_some() && administrator_count(&mut tx).await? == 0 {
            return Err(RoleGuardError::LastAdministrator);
        }
        tx.commit().await?;
        Ok(self.role(role_id).await?)
    }

    /// Deletes a role. `Ok(None)` if it does not exist. Refuses to delete
    /// `@everyone`, and refuses if doing so would leave no administrator.
    ///
    /// Clears the role's channel overwrites by hand: no foreign key ties an
    /// overwrite to a role (the column is polymorphic across role and member
    /// targets), so they would otherwise sit inert but unreachable and the
    /// table would accumulate dead rows. `member_roles` does cascade away on
    /// the role's own foreign key.
    pub async fn delete_role(&self, role_id: RoleId) -> Result<Option<()>, RoleGuardError> {
        // Reads the role and the administrator count before deciding, so it
        // must hold the write lock from the start; see `Store::begin_write`.
        let mut tx = self.begin_write().await?;

        let is_everyone = sqlx::query_scalar!(
            r#"SELECT is_everyone AS "is_everyone!: bool" FROM roles WHERE id = ?"#,
            role_id
        )
        .fetch_optional(&mut *tx)
        .await?;
        let Some(is_everyone) = is_everyone else {
            return Ok(None);
        };
        if is_everyone {
            return Err(RoleGuardError::IsEveryone);
        }

        // Cleared by hand, since no FK covers them; see the note on this
        // function.
        sqlx::query!(
            "DELETE FROM channel_overwrites WHERE target_type = 'role' AND target_id = ?",
            role_id
        )
        .execute(&mut *tx)
        .await?;
        // member_roles cascades away on the role's own foreign key.
        sqlx::query!("DELETE FROM roles WHERE id = ?", role_id)
            .execute(&mut *tx)
            .await?;

        if administrator_count(&mut tx).await? == 0 {
            return Err(RoleGuardError::LastAdministrator);
        }
        tx.commit().await?;
        Ok(Some(()))
    }

    /// Non-`@everyone` role names for a batch of users, in one query no
    /// matter how many are asked about - the same batching shape
    /// [`Store::reactions_for_messages`] uses to keep a page of messages from
    /// paying one query per row. `GET /members` is the caller that actually
    /// needs this: it pages up to 200 members at once, and a naive
    /// per-member roles lookup would be exactly the N+1 that shape exists to
    /// avoid.
    ///
    /// `@everyone` is deliberately excluded: every member holds it, so
    /// including it would put a meaningless badge on every row. A user with
    /// nothing beyond that base role is simply absent from the result, the
    /// same "missing means none" contract [`Store::user_profiles`] already
    /// has for a batch of ids.
    pub async fn roles_for_users(
        &self,
        user_ids: &[UserId],
    ) -> anyhow::Result<Vec<(UserId, Vec<String>)>> {
        if user_ids.is_empty() {
            return Ok(Vec::new());
        }

        // Built rather than a fixed `query!` because the id list is variable
        // length and SQLite has no array binding.
        let mut builder = QueryBuilder::new(
            "SELECT mr.user_id AS user_id, r.name AS name \
             FROM member_roles mr JOIN roles r ON r.id = mr.role_id \
             WHERE r.is_everyone = 0 AND mr.user_id IN (",
        );
        let mut separated = builder.separated(", ");
        for id in user_ids {
            separated.push_bind(*id);
        }
        builder.push(") ORDER BY mr.user_id, r.position DESC, r.created_at");

        let rows = builder.build().fetch_all(&self.pool).await?;

        use sqlx::Row;
        let mut grouped: Vec<(UserId, Vec<String>)> = Vec::new();
        for row in rows {
            let user_id: UserId = row.try_get("user_id")?;
            let name: String = row.try_get("name")?;
            match grouped.iter_mut().find(|(id, _)| *id == user_id) {
                Some((_, names)) => names.push(name),
                None => grouped.push((user_id, vec![name])),
            }
        }
        Ok(grouped)
    }

    /// Revokes a role from a member. Idempotent: unassigning a role the
    /// member does not hold still succeeds, the same as [`Store::assign_role`]
    /// is idempotent the other way. Refuses if doing so would leave no
    /// administrator.
    pub async fn unassign_role(
        &self,
        user_id: UserId,
        role_id: RoleId,
    ) -> Result<(), RoleGuardError> {
        let mut tx = self.pool.begin().await?;
        sqlx::query!(
            "DELETE FROM member_roles WHERE user_id = ? AND role_id = ?",
            user_id,
            role_id
        )
        .execute(&mut *tx)
        .await?;
        if administrator_count(&mut tx).await? == 0 {
            return Err(RoleGuardError::LastAdministrator);
        }
        tx.commit().await?;
        Ok(())
    }
}

/// Counts live users who currently hold ADMINISTRATOR, whether through the
/// `@everyone` base (which applies with no explicit assignment) or a role
/// assigned to them directly.
///
/// Callers run this inside their own transaction, after the mutation under
/// test, so it sees a write that has not committed yet; that is the whole
/// point, since the caller rolls back by simply not committing if this comes
/// back zero.
pub(super) async fn administrator_count(conn: &mut SqliteConnection) -> Result<i64, sqlx::Error> {
    let admin_bit = Permissions::ADMINISTRATOR.bits();
    sqlx::query_scalar!(
        r#"SELECT COUNT(*) AS "count!: i64" FROM users u
           WHERE u.deleted_at IS NULL AND (
               EXISTS (SELECT 1 FROM roles WHERE is_everyone = 1 AND (permissions & ?) != 0)
               OR EXISTS (
                   SELECT 1 FROM member_roles mr JOIN roles r ON r.id = mr.role_id
                   WHERE mr.user_id = u.id AND (r.permissions & ?) != 0
               )
           )"#,
        admin_bit,
        admin_bit
    )
    .fetch_one(&mut *conn)
    .await
}
