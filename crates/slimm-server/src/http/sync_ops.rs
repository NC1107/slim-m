// SPDX-License-Identifier: AGPL-3.0-only
//! The message-op half of `POST /sync`.
//!
//! A sibling of [`super::sync`] rather than part of it, for the line budget.
//!
//! Riding `/sync` rather than taking a route of its own is the opposite of
//! what the canvas op feed does, and the reasons are opposite too: the canvas
//! cursor belongs to an open pane, so putting it here would make every client
//! pay for a surface most never open, while the message cursor is already in
//! `/sync` for exactly these channels and a per-channel route would make a
//! reconnect N requests, which is the one thing `/sync` exists to prevent.

use serde::Serialize;

use super::AppState;
use crate::ids::ChannelId;
use crate::store::{MessageOpEntry, MessageOpKind};

/// An op cursor further behind than this returns `reset` instead of a backlog.
pub(super) const OP_SNAPSHOT_GAP: i64 = 2_000;
/// Most ops returned for one scope.
pub(super) const OPS_PER_SCOPE_LIMIT: i64 = 100;

/// A ceiling on the whole `/sync` response, in bytes of serialized content.
///
/// The message half never had one: `AGGREGATE_LIMIT` bounds it at 500 rows and
/// `MAX_CONTENT_CHARS` bounds each at 4000, so an 8 MB response was already
/// reachable, and ops carry content too. This bounds both halves together
/// rather than giving each its own, since what a client has to hold is the sum.
pub(super) const SYNC_RESPONSE_BYTES: usize = 1024 * 1024;

/// One op on the wire.
///
/// No `actor_id`, on any kind, ever. `Event::MessageDeleted` carries only the
/// ids a live connection needs to drop it from view, and a catch-up feed that
/// named the moderator would hand every member, over a different route,
/// exactly what the live path withholds. The column exists in `message_ops`;
/// this struct deliberately has no field for it.
#[derive(Serialize)]
pub(super) struct MessageOpDto {
    pub seq: i64,
    pub kind: &'static str,
    pub message_id: String,
    pub created_at: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub edited_at: Option<i64>,
}

/// What the ops half contributed to one scope.
pub(super) struct OpsHalf {
    pub ops: Vec<MessageOpDto>,
    pub op_latest_seq: i64,
    pub ops_has_more: bool,
    /// The op cursor could not be answered from the stream, so the caller must
    /// set the response's existing `reset` rather than a flag of its own: the
    /// client's recovery is identical either way, and two flags would be two
    /// names for one path.
    pub reset: bool,
}

/// Reads one scope's ops, or answers empty when the request carried no cursor.
///
/// A request with no `after_op_seq` gets no ops and, crucially, can never be
/// told to reset from an op gap. That is what an older client always sends and
/// what a newer one sends before it has adopted a head, and both take this one
/// branch: evaluating the gap unconditionally is the mutation that would wipe
/// every old client's cache on the first connect after deploy.
pub(super) async fn ops_for_scope(
    state: &AppState,
    channel_id: ChannelId,
    after_op_seq: Option<i64>,
    byte_budget: &mut usize,
) -> anyhow::Result<OpsHalf> {
    let latest = state.store.latest_message_op_seq(channel_id).await?;
    let Some(after) = after_op_seq else {
        return Ok(OpsHalf {
            ops: Vec::new(),
            op_latest_seq: latest,
            ops_has_more: false,
            reset: false,
        });
    };

    let floor = state.store.earliest_message_op_seq(channel_id).await?;
    // `after > latest` is what a Litestream restore produces; see the reset doc.
    let reset = after > latest
        || latest.saturating_sub(after) > OP_SNAPSHOT_GAP
        || floor.is_some_and(|floor| after < floor - 1);
    if reset {
        return Ok(OpsHalf {
            ops: Vec::new(),
            op_latest_seq: latest,
            ops_has_more: false,
            reset: true,
        });
    }

    let page = state
        .store
        .message_ops_since(channel_id, after, OPS_PER_SCOPE_LIMIT + 1)
        .await?;
    let mut entries = page.ops;
    let mut ops_has_more = entries.len() as i64 > OPS_PER_SCOPE_LIMIT;
    entries.truncate(OPS_PER_SCOPE_LIMIT as usize);

    let mut ops: Vec<MessageOpDto> = entries.into_iter().map(dto_from).collect();
    collapse_repeated_content(&mut ops);
    if trim_to_budget(&mut ops, byte_budget) {
        ops_has_more = true;
    }

    Ok(OpsHalf {
        ops,
        op_latest_seq: page.latest_seq,
        ops_has_more,
        reset: false,
    })
}

fn dto_from(entry: MessageOpEntry) -> MessageOpDto {
    let (kind, content, edited_at) = match entry.kind {
        MessageOpKind::Edit => ("edit", entry.content, entry.edited_at),
        MessageOpKind::Delete => ("delete", None, None),
    };
    MessageOpDto {
        seq: entry.seq,
        kind,
        message_id: entry.message_id.to_string(),
        created_at: entry.created_at,
        content,
        edited_at,
    }
}

/// Blanks the content on every op but the last naming a given message.
///
/// Content is the message's *current* text, so a message edited 500 times in
/// one page is 500 copies of the same string, which the byte budget would then
/// truncate into seventeen round trips.
///
/// A blanked op is not dropped: it keeps its seq and its row, so the cursor
/// still advances through it and the client's `+1` adjacency across a page
/// boundary is untouched. Dropping them instead would put a hole in the stream.
fn collapse_repeated_content(ops: &mut [MessageOpDto]) {
    let mut seen: std::collections::HashSet<String> = std::collections::HashSet::new();
    for op in ops.iter_mut().rev() {
        if op.content.is_none() {
            continue;
        }
        if !seen.insert(op.message_id.clone()) {
            op.content = None;
            op.edited_at = None;
        }
    }
}

/// Drops ops from the back until the page fits, answering whether it cut any.
///
/// The first op is always admitted however little budget is left. Without that
/// guarantee one message longer than the whole budget stalls the cursor
/// forever, which is a livelock rather than a slow sync.
fn trim_to_budget(ops: &mut Vec<MessageOpDto>, budget: &mut usize) -> bool {
    let mut kept = 0usize;
    for (i, op) in ops.iter().enumerate() {
        let cost = op.content.as_ref().map_or(0, |c| c.len()) + 64;
        if i > 0 && cost > *budget {
            break;
        }
        *budget = budget.saturating_sub(cost);
        kept = i + 1;
    }
    let trimmed = kept < ops.len();
    ops.truncate(kept);
    trimmed
}
