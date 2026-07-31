// SPDX-License-Identifier: AGPL-3.0-only
//! Direct messages: a DM is a channel of kind [`DM_CHANNEL_KIND`] with one or
//! two participants recorded in `dm_channels`, normalized so the pair (a, b)
//! and (b, a) always resolve to the same row and hence the same channel.
//!
//! A pair may name the same user twice: [`Store::open_dm`] no longer refuses
//! `caller == target`, and that self pair is a personal space rather than a
//! conversation with anyone else - notes that sync across devices the same
//! way any other channel does, with nobody else ever able to reach it.
//!
//! Modelling a DM as a channel is what lets every other feature - sending,
//! editing, keyset pagination, full-text search, bundled sync, push fan-out,
//! and the WebSocket fan-out filter - keep working completely unchanged: all
//! of them already gate on [`Store::has_permission`] /
//! [`Store::permissions_in_channel`], and [`Store::permissions_in_channel`]
//! is the one place taught about the `dm` kind (see [`dm_permissions`]).
//!
//! What is deliberately NOT reused is the role/overwrite evaluator itself.
//! Membership of the pair is the only thing that grants access to a DM, and
//! that has to hold even against `ADMINISTRATOR`, which the ordinary
//! evaluator bypasses everywhere else on purpose. Folding DM access into that
//! evaluator (say, as a synthesized per-member overwrite) would put it one
//! `ADMINISTRATOR` check away from an administrator reading every DM on the
//! deployment; a separate explicit check has no such bypass to accidentally
//! inherit.

use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;

use super::{Channel, Store, User, now_ms};

pub(crate) const DM_CHANNEL_KIND: &str = "dm";

/// Everything a DM participant can ever do inside it. Deliberately narrower
/// than [`Permissions::ALL`]: there is no moderation, no roles, and no
/// canvas or voice inside a DM, only a conversation between two people.
const DM_BASE: Permissions = Permissions::VIEW_CHANNEL
    .union(Permissions::SEND_MESSAGES)
    .union(Permissions::ADD_REACTIONS)
    .union(Permissions::ATTACH_FILES);

/// What a block removes: everything that creates new content. `VIEW_CHANNEL`
/// survives so a block stops a conversation without erasing it; a party who
/// blocked (or was blocked by) the other can still read what already
/// happened, and it also means an out-of-band delete of `user_blocks` cannot
/// double as a way to silently reopen a hidden history.
const BLOCKED_DENY: Permissions = Permissions::SEND_MESSAGES
    .union(Permissions::ADD_REACTIONS)
    .union(Permissions::ATTACH_FILES);

/// Why opening a DM failed.
#[derive(Debug)]
pub enum OpenDmError {
    /// The target account does not exist, or has been deleted.
    UserNotFound,
    /// Either party has blocked the other.
    Blocked,
    Internal(anyhow::Error),
}

impl From<sqlx::Error> for OpenDmError {
    fn from(err: sqlx::Error) -> Self {
        OpenDmError::Internal(err.into())
    }
}

impl From<anyhow::Error> for OpenDmError {
    fn from(err: anyhow::Error) -> Self {
        OpenDmError::Internal(err)
    }
}

/// One of the caller's DM conversations: the channel, the other participant's
/// public profile, and the caller's own unread count in it - exactly what the
/// client's Direct Messages rail renders.
#[derive(Debug, Clone)]
pub struct DmConversation {
    pub channel_id: ChannelId,
    pub other: User,
    pub unread: i64,
    pub created_at: i64,
}

/// Orders a pair so (a, b) and (b, a) always produce the same result. `Uuid`
/// orders by its raw bytes, the same order SQLite compares a `BLOB` column
/// with, so this matches the `CHECK (user_a <= user_b)` constraint the
/// migration puts on the table. A self pair (a == b) is already ordered
/// either way this branches, which is exactly what admits it.
fn normalize_pair(a: UserId, b: UserId) -> (UserId, UserId) {
    if a.0 < b.0 { (a, b) } else { (b, a) }
}

impl Store {
    /// Opens the DM channel between two users, creating it on first contact.
    /// `caller == target` opens (or returns) the caller's own personal space
    /// rather than being refused: see the module doc comment.
    ///
    /// Idempotent and race-safe: two callers opening the same pair at once
    /// converge on one channel, never two. This reads whether the pair
    /// already has a channel before deciding whether to create one, so it
    /// uses [`Store::begin_write`] (`BEGIN IMMEDIATE`) rather than a plain
    /// transaction: a deferred transaction that has already taken a read
    /// snapshot cannot promote itself to a writer if another connection
    /// takes the write lock first, and SQLite reports that as SQLITE_BUSY
    /// immediately rather than waiting. Taking the write lock up front
    /// instead makes a second concurrent open queue behind the first (up to
    /// the pool's `busy_timeout`) and then find the row the first one just
    /// committed, rather than racing it to insert a second one.
    ///
    /// Blocking is checked before the pair table is even touched, so a blocked
    /// relationship never learns whether a channel already exists between
    /// them, and a re-open is refused exactly as the first open would be.
    pub async fn open_dm(&self, caller: UserId, target: UserId) -> Result<Channel, OpenDmError> {
        if self.user_profile(target).await?.is_none() {
            return Err(OpenDmError::UserNotFound);
        }
        // A self pair can never be blocked (refused at the HTTP layer), so skip it.
        if caller != target
            && (self.has_blocked(caller, target).await? || self.has_blocked(target, caller).await?)
        {
            return Err(OpenDmError::Blocked);
        }

        let (user_a, user_b) = normalize_pair(caller, target);
        let mut tx = self.begin_write().await?;

        if let Some(channel_id) = sqlx::query_scalar!(
            r#"SELECT channel_id AS "channel_id!: ChannelId"
               FROM dm_channels WHERE user_a = ? AND user_b = ?"#,
            user_a,
            user_b
        )
        .fetch_optional(&mut *tx)
        .await?
        {
            tx.commit().await?;
            return self.channel(channel_id).await?.ok_or_else(|| {
                anyhow::anyhow!("dm_channels row exists but its channel does not").into()
            });
        }

        let channel_id = ChannelId::generate();
        let now = now_ms();
        // A DM has no name of its own; the client renders the other
        // participant's display name instead, carried on `DmConversation`.
        sqlx::query!(
            "INSERT INTO channels (id, name, kind, created_at) VALUES (?, '', 'dm', ?)",
            channel_id,
            now
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO channel_seq_counters (channel_id, stream, next_seq)
             VALUES (?, 'message', 1), (?, 'canvas', 1)",
            channel_id,
            channel_id
        )
        .execute(&mut *tx)
        .await?;
        sqlx::query!(
            "INSERT INTO dm_channels (channel_id, user_a, user_b, created_at)
             VALUES (?, ?, ?, ?)",
            channel_id,
            user_a,
            user_b,
            now
        )
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;

        Ok(Channel {
            id: channel_id,
            name: String::new(),
            kind: DM_CHANNEL_KIND.to_owned(),
            topic: None,
            created_at: now,
        })
    }

    /// The caller's DM conversations, most recently active first. A
    /// conversation whose other participant has been deleted is omitted
    /// rather than shown with nothing to render for them.
    pub async fn list_dm_conversations(
        &self,
        user_id: UserId,
    ) -> anyhow::Result<Vec<DmConversation>> {
        let rows = sqlx::query!(
            r#"SELECT d.channel_id AS "channel_id!: ChannelId",
                      CASE WHEN d.user_a = ? THEN d.user_b ELSE d.user_a END AS "other_id!: UserId",
                      c.created_at AS "created_at!",
                      COALESCE(
                          (SELECT MAX(m.created_at) FROM messages m
                           WHERE m.channel_id = d.channel_id AND m.deleted_at IS NULL),
                          c.created_at
                      ) AS "activity_at!: i64"
               FROM dm_channels d
               JOIN channels c ON c.id = d.channel_id AND c.deleted_at IS NULL
               WHERE d.user_a = ? OR d.user_b = ?
               ORDER BY "activity_at!: i64" DESC"#,
            user_id,
            user_id,
            user_id
        )
        .fetch_all(&self.pool)
        .await?;

        let mut conversations = Vec::with_capacity(rows.len());
        for row in rows {
            let Some(other) = self.user_profile(row.other_id).await? else {
                continue;
            };
            let unread = self.unread_count(user_id, row.channel_id).await?;
            conversations.push(DmConversation {
                channel_id: row.channel_id,
                other,
                unread,
                created_at: row.created_at,
            });
        }
        Ok(conversations)
    }

    /// The explicit DM authorization check that [`Store::permissions_in_channel`]
    /// delegates to for a `dm`-kind channel, instead of running the ordinary
    /// role/overwrite evaluator. A caller outside the pair gets
    /// [`Permissions::NONE`] regardless of any role they hold -
    /// `ADMINISTRATOR` included, since that bypass belongs to the
    /// deployment's own channels, not to a conversation between two
    /// specific people who happen to be on it.
    /// The two accounts a DM channel is between, or `None` if it is not a DM.
    ///
    /// Exists so a caller with many candidates can narrow them to the pair
    /// before asking anything per candidate; see [`Store::viewers_among`].
    pub(crate) async fn dm_pair(
        &self,
        channel_id: ChannelId,
    ) -> anyhow::Result<Option<(UserId, UserId)>> {
        let pair = sqlx::query!(
            r#"SELECT user_a AS "user_a!: UserId", user_b AS "user_b!: UserId"
               FROM dm_channels WHERE channel_id = ?"#,
            channel_id
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(pair.map(|p| (p.user_a, p.user_b)))
    }

    pub(crate) async fn dm_permissions(
        &self,
        user_id: UserId,
        channel_id: ChannelId,
    ) -> anyhow::Result<Permissions> {
        let pair = sqlx::query!(
            r#"SELECT user_a AS "user_a!: UserId", user_b AS "user_b!: UserId"
               FROM dm_channels WHERE channel_id = ?"#,
            channel_id
        )
        .fetch_optional(&self.pool)
        .await?;
        let Some(pair) = pair else {
            return Ok(Permissions::NONE);
        };

        let other = if user_id == pair.user_a {
            pair.user_b
        } else if user_id == pair.user_b {
            pair.user_a
        } else {
            return Ok(Permissions::NONE);
        };

        // A personal space's "other" party is the caller themself; see open_dm.
        if other != user_id
            && (self.has_blocked(user_id, other).await? || self.has_blocked(other, user_id).await?)
        {
            return Ok(DM_BASE.remove(BLOCKED_DENY));
        }
        Ok(DM_BASE)
    }
}
