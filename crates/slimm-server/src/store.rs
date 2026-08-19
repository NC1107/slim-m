// SPDX-License-Identifier: AGPL-3.0-only
//! The persistence layer over one embedded SQLite database: the [`Store`]
//! handle itself, the domain types shared across every feature submodule, and
//! the handful of methods (account creation, liveness, live user ids) that do
//! not belong to any single feature area.
//!
//! Everything else is split by feature, mirroring the HTTP surface: messages
//! (send, edit, delete, list, search) in [`messages`], channel CRUD in
//! [`channels`], user profiles and the member list in [`users`], reactions in
//! [`reactions`], and so on. This is inherent on [`Store`] for now; it lifts
//! to a repository trait when a second backend (Postgres) actually needs one.

use std::sync::Arc;

use sqlx::SqlitePool;

use crate::ids::{ChannelCategoryId, ChannelId, MessageId, Seq, UserId};

mod account_deletion;
mod analytics;
mod attachments;
mod bootstrap;
mod canvas;
mod canvas_audit;
mod canvas_media_slots;
mod canvas_move;
mod canvas_op_clock;
mod canvas_ops;
mod canvas_ops_apply;
mod canvas_ops_sweep;
mod canvas_ops_write;
mod categories;
mod channel_notification_prefs;
mod channel_order;
mod channels;
mod dms;
mod emoji;
mod invites;
mod message_history;
mod message_ops;
mod message_retention;
mod message_search;
mod messages;
mod messages_bulk;
mod moderation_audit;
mod notifications;
mod permissions;
mod permissions_batch;
mod pins;
mod polls;
mod presence;
mod push;
mod reactions;
mod read_state;
mod recovery;
mod removals;
mod reports;
mod roles;
mod safety;
mod sessions;
mod space;
mod thread_listing;
mod threads;
mod timeouts;
mod users;

pub use account_deletion::DeleteAccountError;
pub use analytics::{
    ANALYTICS_WINDOW_DAYS, AnalyticsStats, DayCount, MemberAttachmentUsage, MetricSample,
};
pub use attachments::{AttachmentSummary, LinkError, MAX_ATTACHMENTS_PER_MESSAGE};
pub use bootstrap::Bootstrap;
pub use canvas::{
    CanvasObject, MAX_OBJECT_EXTENT, MAX_OBJECTS_PER_CHANNEL, PlaceError, PlaceRequest, Placement,
    Rect, ViewportQuery, WORLD_LIMIT,
};
pub use canvas_media_slots::{CanvasMediaSlot, MediaSlotError, MediaSlotKind};
pub use canvas_ops::{
    CANVAS_OP_GAP, CANVAS_OP_PAGE_BYTES, CanvasOpBody, CanvasOpEntry, CanvasOpsPage,
};
pub use canvas_ops_sweep::{CANVAS_OP_RETENTION_MS, SweptCanvasOps};
pub use canvas_ops_write::{CanvasOpRequest, MAX_REMOVE_IDS_PER_OP, SubmitOpError, SubmittedOp};
pub use channel_order::{ChannelOrderGroup, ReorderChannelsError, ReorderOutcome};
pub use channels::DeleteChannelError;
pub(crate) use dms::DM_CHANNEL_KIND;
pub use dms::{DmConversation, OpenDmError};
pub use emoji::{CreateEmojiError, CustomEmoji, MAX_CUSTOM_EMOJI};
pub use invites::{Invite, InviteCheck, InviteMetadata, RedeemError};
pub use message_history::MessageRevision;
pub use message_ops::{MessageOpEntry, MessageOpKind, MessageOpsPage};
pub use message_retention::{MAX_MESSAGE_RETENTION_DAYS, PrunedMessage, SweptMessageRetention};
pub use message_search::{MessageSearchFilters, SearchError};
pub use messages::{Edited, MessageDeletion, SendError, Sent};
pub use messages_bulk::{BulkDeleteError, BulkDeletion, DeletedMessage};
pub use pins::{MAX_PINS_PER_CHANNEL, PinError, PinnedMessage};
pub use polls::{
    CreatePollError, MAX_OPTION_CHARS, MAX_OPTIONS, MAX_QUESTION_CHARS, MIN_OPTIONS, Poll,
    PollOption, PollTally, VoteError,
};
pub use push::{PushError, PushRegistration, PushTarget};
pub use reactions::{MAX_EMOJI_BYTES, ReactError, ReactionSummary};
pub use recovery::{ConsumeResetError, IssueResetError};
pub use removals::{RemoveMemberError, SpaceRemoval};
pub use reports::{Report, ReportError, ReportSubject};
pub use roles::{Role, RoleGuardError};
pub use safety::Device;
pub use sessions::{
    Account, IssuedTokens, OpenError, RefreshOutcome, RegisterError, SessionContext, SweptTokens,
};
pub use space::JoinPolicy;
pub use thread_listing::ThreadListItem;
pub use threads::{
    MAX_THREADS_PER_CHANNEL, OpenThreadError, OpenedThread, ThreadParent, ThreadSummary,
};
pub use timeouts::{MAX_TIMEOUT_MS, MemberTimeout};

/// Unix milliseconds, `pub(crate)` so the push trigger path (outside this
/// module) can compare a lifecycle report's age against the same clock
/// everything here is stamped with.
pub(crate) fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

/// A channel (a text or voice room).
#[derive(Debug, Clone)]
pub struct Channel {
    pub id: ChannelId,
    pub name: String,
    pub kind: String,
    /// A one-line description shown beside the name in the client's channel
    /// header. `None` for no topic, distinct from an empty string: clearing
    /// it back to `None` is what an edit to a blank value normalizes to, the
    /// same way an empty topic and no topic render identically to a viewer.
    pub topic: Option<String>,
    /// Sort key among the deployment's live, non-DM channels: lower sorts
    /// first. Deployment-wide, not per-device - see
    /// [`super::channel_order::reorder_channels`]. Meaningless for a DM,
    /// which is never listed or reordered by it.
    pub position: i64,
    /// The message this channel is a thread of, or `None` for an ordinary
    /// channel. A thread's own `kind` and overwrites are never consulted for
    /// permissions: see [`Store::permission_channel`], which resolves them
    /// live from this message's own `channel_id` instead, per
    /// docs/decisions/0005-threads.md. A thread never appears in
    /// [`Store::list_channels`].
    pub parent_message_id: Option<MessageId>,
    /// The rail section this channel is filed under, or `None` for
    /// uncategorised - rendered as an implicit section above every named
    /// one. Decides placement only, never behaviour: see
    /// docs/decisions/0006-channel-categories.md. A category carries no
    /// permissions of its own, so this column is never consulted by
    /// [`Store::permission_channel`] or anything it calls.
    pub category_id: Option<ChannelCategoryId>,
    pub created_at: i64,
}

/// A rail section: a channel of any kind may be filed under one, per
/// docs/decisions/0006-channel-categories.md. Organisational only - it
/// grants and denies no permission, see docs/IMPLIED-GAPS.md.
#[derive(Debug, Clone)]
pub struct ChannelCategory {
    pub id: ChannelCategoryId,
    pub name: String,
    /// Sort key among the deployment's live categories: lower sorts first.
    /// Uncategorised channels render above every named category regardless
    /// of this value, since they carry no category row to hold one.
    pub position: i64,
    pub created_at: i64,
}

/// A user account's public profile. Deliberately narrow: id, username,
/// display name, and creation time only. Nothing from the auth tables
/// (password hash, sessions, tokens) has a type that could even be confused
/// with this one.
#[derive(Debug, Clone)]
pub struct User {
    pub id: UserId,
    pub username: String,
    pub display_name: String,
    pub created_at: i64,
    /// When the caller's current avatar was set, or `None` for no avatar.
    /// Not a foreign key to anything: the bytes live on disk keyed by user
    /// id, not content-addressed like a message attachment (see migration
    /// 0013). A client uses the value only as a cache-busting version
    /// appended to the fetch URL.
    pub avatar_updated_at: Option<i64>,
    /// A short free-text status line ("in a meeting", "afk"), or `None` for
    /// none set. Rides alongside `display_name` (migration 0044): set from
    /// personal settings, shown in the member pane under the name, and
    /// carries no independent live event - `Event::ProfileChanged` already
    /// covers it the same way it covers a rename.
    pub status_text: Option<String>,
}

/// A message. `author_id` is null once the author's account is anonymized.
///
/// The author's display name rides along with the message rather than being
/// looked up per author by the client, which would be a request per distinct
/// sender in a channel. It is null for the same reason `author_id` is: the
/// account was anonymized, and there is no name left to show.
#[derive(Debug, Clone)]
pub struct Message {
    pub id: MessageId,
    pub channel_id: ChannelId,
    pub author_id: Option<UserId>,
    pub author_display_name: Option<String>,
    pub seq: Seq,
    pub content: String,
    pub created_at: i64,
    pub edited_at: Option<i64>,
    /// The message this one replies to, if any. Always in this same channel:
    /// [`Store::send_message`] refuses any other target at write time. The
    /// parent's own content, author and liveness are never copied here -
    /// resolve them by looking that id up like any other message, so a
    /// later edit or delete of the parent is never something a reply's own
    /// row could go stale about.
    pub reply_to_id: Option<MessageId>,
}

/// How recently a spent refresh token may be replayed before it counts as reuse
/// rather than the honest client racing itself. See [`Store::rotate_refresh`].
const DEFAULT_REUSE_GRACE_MS: i64 = 10 * 1000;

/// The persistence layer over one embedded SQLite database.
#[derive(Clone)]
pub struct Store {
    pool: SqlitePool,
    reuse_grace_ms: i64,
    /// Backs [`canvas_op_clock::Store::now_ms_unique`]. `Arc`-shared so every
    /// clone of one `Store` sees the same clock, and fresh on every new
    /// `Store` - which is what makes it fresh on every process restart too,
    /// since a restart constructs a brand new one rather than reusing state
    /// that outlived the process. See that method's own doc for why a fresh,
    /// unseeded clock is the exact gap the seeding step closes.
    canvas_op_clock: Arc<canvas_op_clock::CanvasOpClock>,
}

impl Store {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            pool,
            reuse_grace_ms: DEFAULT_REUSE_GRACE_MS,
            canvas_op_clock: Arc::default(),
        }
    }

    /// Builds a store with an explicit refresh-reuse grace window. Mainly for
    /// tests that need to exercise the out-of-grace reuse path deterministically.
    pub fn with_reuse_grace_ms(pool: SqlitePool, reuse_grace_ms: i64) -> Self {
        Self {
            pool,
            reuse_grace_ms,
            canvas_op_clock: Arc::default(),
        }
    }

    /// Confirms the database answers a trivial query. Backs the liveness probe.
    pub async fn ping(&self) -> anyhow::Result<()> {
        sqlx::query("SELECT 1").execute(&self.pool).await?;
        Ok(())
    }

    /// Opens a transaction that takes SQLite's write lock immediately.
    ///
    /// The pool hands out eight connections and any of them may write, so two
    /// requests really can be inside a transaction at once. A plain `BEGIN` is
    /// deferred: it takes a read snapshot on its first statement and only tries
    /// for the write lock later. If another connection took that lock in
    /// between, the upgrade cannot wait, because two readers both waiting to
    /// become writers would deadlock, so SQLite returns SQLITE_BUSY at once and
    /// `busy_timeout` never comes into it.
    ///
    /// Any transaction whose first statement is a write already avoids this by
    /// construction, which is what most of the store does deliberately (see
    /// [`Store::rotate_refresh`]). Use this for the ones that genuinely have to
    /// read before they decide what to write.
    pub(crate) async fn begin_write(
        &self,
    ) -> Result<sqlx::Transaction<'_, sqlx::Sqlite>, sqlx::Error> {
        self.pool.begin_with("BEGIN IMMEDIATE").await
    }

    /// Creates a passwordless user. Used by tests and internal fixtures; the
    /// authenticated registration path is [`Store::create_account`].
    pub async fn create_user(&self, username: &str, display_name: &str) -> anyhow::Result<User> {
        let id = UserId::generate();
        let now = now_ms();
        sqlx::query!(
            "INSERT INTO users (id, username, display_name, created_at) VALUES (?, ?, ?, ?)",
            id,
            username,
            display_name,
            now
        )
        .execute(&self.pool)
        .await?;
        Ok(User {
            id,
            username: username.to_owned(),
            display_name: display_name.to_owned(),
            created_at: now,
            avatar_updated_at: None,
            status_text: None,
        })
    }

    /// The server's long-lived identity keypair, generating and persisting
    /// one on the first call a fresh deployment ever makes. See
    /// [`crate::identity`] for what a client may and may not conclude from it.
    pub async fn server_identity(&self) -> anyhow::Result<crate::identity::ServerIdentity> {
        crate::identity::load_or_create(&self.pool).await
    }

    /// This deployment's display name, shown to a prospective joiner (invite
    /// metadata) before they have an account.
    ///
    /// Backed by `server_meta` rather than a dedicated column: it is exactly
    /// the kind of singleton deployment-wide setting that table already
    /// exists for, seeded with a default by migration 0010. The fallback
    /// here is defensive only (every deployment gets the seeded row), not a
    /// substitute for it.
    pub async fn deployment_name(&self) -> anyhow::Result<String> {
        let value = sqlx::query_scalar!(
            r#"SELECT value AS "value!" FROM server_meta WHERE key = 'deployment_name'"#
        )
        .fetch_optional(&self.pool)
        .await?;
        Ok(value.unwrap_or_else(|| "slim-m".to_owned()))
    }
}
