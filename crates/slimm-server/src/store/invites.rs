// SPDX-License-Identifier: AGPL-3.0-only
//! Invites: how someone joins a self-hosted deployment.
//!
//! Registration is open on an unclaimed server so the first account can claim
//! it, but a real deployment wants joining to be by invitation. An invite is a
//! short code with an optional use limit and expiry, and redeeming one is what
//! turns a registration into a member.

use rand_core::{OsRng, RngCore};

use super::{Store, now_ms};
use crate::ids::{RoleId, UserId};

/// A code someone can join with.
#[derive(Debug, Clone)]
pub struct Invite {
    pub code: String,
    pub max_uses: Option<i64>,
    pub uses: i64,
    pub expires_at: Option<i64>,
    pub created_at: i64,
    pub revoked: bool,
}

impl Invite {
    /// Whether this invite can still be used right now.
    pub fn is_usable(&self, now: i64) -> bool {
        !self.revoked
            && self.max_uses.is_none_or(|max| self.uses < max)
            && self.expires_at.is_none_or(|expiry| expiry > now)
    }
}

/// Why redeeming failed. Deliberately one variant from the caller's point of
/// view: an expired code, a used-up code, and a code that never existed are all
/// reported the same way, so the endpoint cannot be used to mine valid codes.
#[derive(Debug)]
pub enum RedeemError {
    Unusable,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for RedeemError {
    fn from(err: sqlx::Error) -> Self {
        RedeemError::Internal(err.into())
    }
}

/// Generates a short, unambiguous code. Avoids characters people misread when
/// reading a code aloud or copying it off a screen.
fn generate_code() -> String {
    const ALPHABET: &[u8] = b"abcdefghjkmnpqrstuvwxyz23456789";
    let mut bytes = [0u8; 10];
    OsRng.fill_bytes(&mut bytes);
    bytes
        .iter()
        .map(|b| ALPHABET[*b as usize % ALPHABET.len()] as char)
        .collect()
}

impl Store {
    /// Creates an invite.
    pub async fn create_invite(
        &self,
        created_by: UserId,
        role_grant: Option<RoleId>,
        max_uses: Option<i64>,
        expires_at: Option<i64>,
    ) -> anyhow::Result<Invite> {
        let code = generate_code();
        let now = now_ms();
        sqlx::query!(
            "INSERT INTO invites (code, created_by, role_grant, max_uses, expires_at, created_at)
             VALUES (?, ?, ?, ?, ?, ?)",
            code,
            created_by,
            role_grant,
            max_uses,
            expires_at,
            now
        )
        .execute(&self.pool)
        .await?;
        Ok(Invite {
            code,
            max_uses,
            uses: 0,
            expires_at,
            created_at: now,
            revoked: false,
        })
    }

    /// The deployment's invites, newest first.
    pub async fn list_invites(&self) -> anyhow::Result<Vec<Invite>> {
        let rows = sqlx::query!(
            r#"SELECT code AS "code!", max_uses, uses AS "uses!", expires_at,
                      created_at AS "created_at!", revoked_at
               FROM invites ORDER BY created_at DESC"#
        )
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| Invite {
                code: r.code,
                max_uses: r.max_uses,
                uses: r.uses,
                expires_at: r.expires_at,
                created_at: r.created_at,
                revoked: r.revoked_at.is_some(),
            })
            .collect())
    }

    pub async fn revoke_invite(&self, code: &str) -> anyhow::Result<()> {
        let now = now_ms();
        sqlx::query!(
            "UPDATE invites SET revoked_at = ? WHERE code = ? AND revoked_at IS NULL",
            now,
            code
        )
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    /// Whether a code could be redeemed, without spending it. Used to check a
    /// code before asking someone to fill in a whole signup form.
    pub async fn invite_is_usable(&self, code: &str) -> anyhow::Result<bool> {
        let now = now_ms();
        let row = sqlx::query!(
            r#"SELECT max_uses, uses AS "uses!", expires_at, revoked_at
               FROM invites WHERE code = ?"#,
            code
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.is_some_and(|r| {
            r.revoked_at.is_none()
                && r.max_uses.is_none_or(|max| r.uses < max)
                && r.expires_at.is_none_or(|expiry| expiry > now)
        }))
    }

    /// Spends one use of an invite and applies any role it grants.
    ///
    /// The spend is a single conditional UPDATE, so the use limit holds under
    /// concurrent redemptions: two people racing the last slot cannot both win,
    /// because only one UPDATE can match.
    pub async fn redeem_invite(&self, code: &str, user_id: UserId) -> Result<(), RedeemError> {
        let now = now_ms();
        let mut tx = self.pool.begin().await?;

        let claimed = sqlx::query!(
            r#"UPDATE invites SET uses = uses + 1
               WHERE code = ?
                 AND revoked_at IS NULL
                 AND (max_uses IS NULL OR uses < max_uses)
                 AND (expires_at IS NULL OR expires_at > ?)
               RETURNING role_grant AS "role_grant: RoleId""#,
            code,
            now
        )
        .fetch_optional(&mut *tx)
        .await?;

        let Some(claimed) = claimed else {
            return Err(RedeemError::Unusable);
        };

        if let Some(role_id) = claimed.role_grant {
            sqlx::query!(
                "INSERT OR IGNORE INTO member_roles (user_id, role_id) VALUES (?, ?)",
                user_id,
                role_id
            )
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(())
    }
}
