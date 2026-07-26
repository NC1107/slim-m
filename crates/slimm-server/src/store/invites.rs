// SPDX-License-Identifier: AGPL-3.0-only
//! Invites: how someone joins a self-hosted deployment.
//!
//! Registration is open on an unclaimed server so the first account can claim
//! it, but a real deployment wants joining to be by invitation. An invite is a
//! short code with an optional use limit and expiry.
//!
//! A code is spent in one of two places, both through [`spend_invite`] so they
//! cannot drift apart:
//!
//! - [`Store::register_account`], which is how somebody without an account
//!   joins a claimed deployment. The spend happens in the same transaction as
//!   the account insert, so neither half can land without the other.
//! - [`Store::redeem_invite`], for an account that already exists and is
//!   spending a code for the role it grants.

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

/// What a valid invite discloses about itself, returned only for a code
/// [`Store::check_invite`] found usable. See that method's doc comment for
/// why the usable/unusable boundary is where this can be disclosed at all.
#[derive(Debug, Clone)]
pub struct InviteMetadata {
    /// The inviter's current display name, or `None` if their account has
    /// since been deleted: there is no name left to show, the same rule a
    /// message's author display name follows once its author is anonymized.
    pub invited_by: Option<String>,
    /// How many uses are left. `None` means unlimited.
    pub uses_remaining: Option<i64>,
    /// Unix milliseconds. `None` means the invite never expires.
    pub expires_at: Option<i64>,
}

/// The result of checking a code before signup.
#[derive(Debug, Clone)]
pub enum InviteCheck {
    /// Expired, spent, revoked, or never issued. Deliberately one variant
    /// for all four: see the module doc comment.
    Unusable,
    Usable(InviteMetadata),
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

    /// Whether a code could be redeemed, without spending it. A thin
    /// boolean view over [`Store::check_invite`] for callers (and existing
    /// tests) that only need the yes/no answer.
    pub async fn invite_is_usable(&self, code: &str) -> anyhow::Result<bool> {
        Ok(matches!(
            self.check_invite(code).await?,
            InviteCheck::Usable(_)
        ))
    }

    /// Checks a code before asking someone to fill in a whole signup form,
    /// without spending it.
    ///
    /// The unusable branch answers identically for a code that is expired,
    /// already spent, revoked, or was never issued at all: [`InviteCheck`]
    /// has exactly one variant for all four, so there is no field this
    /// method (or its caller) could even accidentally leak that would let a
    /// caller distinguish one from another. The usable branch is different:
    /// a caller reaching it has already demonstrated they hold a working
    /// code, so [`InviteMetadata`] discloses what that code unlocks. That is
    /// new information about the deployment, not about the code itself, and
    /// it is safe only because proving the code works came first.
    pub async fn check_invite(&self, code: &str) -> anyhow::Result<InviteCheck> {
        let now = now_ms();
        let row = sqlx::query!(
            r#"SELECT max_uses, uses AS "uses!", expires_at, revoked_at,
                      u.display_name AS "invited_by?: String"
               FROM invites i
               LEFT JOIN users u ON u.id = i.created_by AND u.deleted_at IS NULL
               WHERE i.code = ?"#,
            code
        )
        .fetch_optional(&self.pool)
        .await?;

        let Some(row) = row else {
            return Ok(InviteCheck::Unusable);
        };
        let usable = row.revoked_at.is_none()
            && row.max_uses.is_none_or(|max| row.uses < max)
            && row.expires_at.is_none_or(|expiry| expiry > now);
        if !usable {
            return Ok(InviteCheck::Unusable);
        }

        Ok(InviteCheck::Usable(InviteMetadata {
            invited_by: row.invited_by,
            uses_remaining: row.max_uses.map(|max| max - row.uses),
            expires_at: row.expires_at,
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

        let Some(role_grant) = spend_invite(&mut tx, code, now).await? else {
            return Err(RedeemError::Unusable);
        };

        if let Some(role_id) = role_grant {
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

/// Spends one use of `code` inside an open transaction.
///
/// `Ok(None)` means the code was unusable: expired, spent, revoked, or never
/// there. `Ok(Some(grant))` means this caller won the use, and `grant` is the
/// role the invite carries, if any.
///
/// A single conditional UPDATE is what makes the use limit hold under
/// concurrency: two callers racing the last slot cannot both match. It lives
/// here as a free function so registration ([`Store::register_account`]) and
/// redemption by an existing account ([`Store::redeem_invite`]) spend a code
/// through exactly the same statement, and cannot drift into two different
/// notions of what "usable" means.
pub(super) async fn spend_invite(
    tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
    code: &str,
    now: i64,
) -> Result<Option<Option<RoleId>>, sqlx::Error> {
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
    .fetch_optional(&mut **tx)
    .await?;
    Ok(claimed.map(|row| row.role_grant))
}
