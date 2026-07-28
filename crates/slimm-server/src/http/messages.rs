// SPDX-License-Identifier: AGPL-3.0-only
//! Message HTTP routes: send, list, edit, and delete, each authorized
//! server-side through the permission evaluator. Full-text search lives in
//! [`super::search`], a separate module since it has its own validation and
//! error handling.
//!
//! Sends are idempotent by the client-supplied message id, so an at-least-once
//! client that retries never duplicates. Every handler checks permissions in the
//! target channel before touching the store: view to read, view plus send to
//! post, and authorship or manage-messages to edit or delete.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, patch};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, Json, Query, enforce};
use super::polls::PollDto;
use crate::hub::Event;
use crate::ids::{ChannelId, MessageId, UserId};
use crate::media;
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{AttachmentSummary, MAX_ATTACHMENTS_PER_MESSAGE, Message};

/// Message bodies carry one text field; cap it generously but bounded.
const MESSAGE_BODY_LIMIT: usize = 64 * 1024;
/// Longest a single message may be, in characters.
const MESSAGE_MAX_CHARS: usize = 4000;
/// Default and maximum page sizes for history.
const DEFAULT_LIMIT: i64 = 50;
const MAX_LIMIT: i64 = 100;

/// The message routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/channels/{channel_id}/messages", get(list).post(send))
        .route(
            "/channels/{channel_id}/messages/{message_id}",
            patch(edit).delete(delete),
        )
        .layer(DefaultBodyLimit::max(MESSAGE_BODY_LIMIT))
}

// --- Wire types ---

#[derive(Serialize)]
pub(crate) struct MessageDto {
    id: String,
    channel_id: String,
    author_id: Option<String>,
    /// Null once the author's account is anonymized, which is also when
    /// `author_id` goes null. Clients render their own fallback rather than
    /// being handed a server-invented placeholder.
    author_display_name: Option<String>,
    seq: i64,
    content: String,
    created_at: i64,
    edited_at: Option<i64>,
    /// Empty unless the caller asked for a list, which is the only path that
    /// batch-loads them; a single echoed message carries none because it
    /// cannot have any yet.
    #[serde(default)]
    reactions: Vec<ReactionDto>,
    /// The poll this message carries, if any. Always present as a key (never
    /// omitted): `null` means this message is not a poll, the same "always
    /// there, empty or null means genuinely none" convention `reactions`
    /// already follows. Set by [`super::polls::attach_polls`], not by this
    /// conversion, since a bare `Message` has nowhere to read poll data from.
    pub(crate) poll: Option<PollDto>,
    /// Always present, empty when there are none - same convention as
    /// `reactions`. Unlike reactions and polls, a fresh send can carry these
    /// immediately (they are uploaded before the send, then referenced in
    /// it), so the send path reads them once and fills this in on both its
    /// own response and the live frame, rather than leaving it empty the way
    /// `reactions` is left empty for a message that cannot have any yet.
    #[serde(default)]
    pub(crate) attachments: Vec<AttachmentDto>,
}

/// One attachment as it appears on a message.
#[derive(Serialize, Clone)]
pub(crate) struct AttachmentDto {
    id: String,
    filename: String,
    content_type: String,
    size: i64,
}

impl From<AttachmentSummary> for AttachmentDto {
    fn from(a: AttachmentSummary) -> Self {
        Self {
            id: a.id,
            filename: a.filename,
            content_type: a.content_type,
            size: a.size,
        }
    }
}

/// One emoji on a message, with the asking user's own state.
#[derive(Serialize)]
pub(crate) struct ReactionDto {
    emoji: String,
    count: i64,
    /// Whether the caller reacted with this emoji, so the client can render the
    /// toggled state without a second request.
    reacted: bool,
}

impl From<Message> for MessageDto {
    fn from(message: Message) -> Self {
        Self {
            id: message.id.to_string(),
            channel_id: message.channel_id.to_string(),
            author_id: message.author_id.map(|id| id.to_string()),
            author_display_name: message.author_display_name,
            seq: message.seq.0,
            content: message.content,
            created_at: message.created_at,
            edited_at: message.edited_at,
            reactions: Vec::new(),
            poll: None,
            attachments: Vec::new(),
        }
    }
}

#[derive(Deserialize)]
struct SendRequest {
    /// Client-generated UUID (v7 preferred) that makes the send idempotent.
    id: String,
    content: String,
    /// Hex sha256 ids of attachments already uploaded through
    /// `POST /attachments`, in display order. Capped at
    /// [`MAX_ATTACHMENTS_PER_MESSAGE`]; referencing an id that was never
    /// uploaded (or was already swept as an orphan) is a 400, not a silent
    /// drop.
    #[serde(default)]
    attachment_ids: Vec<String>,
}

#[derive(Deserialize)]
struct EditRequest {
    content: String,
}

#[derive(Deserialize)]
struct ListParams {
    before: Option<i64>,
    limit: Option<i64>,
}

// --- Handlers ---

/// Sends a message, idempotent by the client-generated message id.
///
/// A nonexistent channel grants no permissions, so this refuses both "you
/// cannot post here" and "no such channel" identically, revealing neither.
/// ATTACH_FILES is only demanded when the send actually carries something, so
/// an ordinary text message never needs it.
///
/// A retry of a send that already succeeded returns the stored message so the
/// client gets its acknowledgement, but must not repeat what already happened
/// once. Fanning it out again would show it twice to anyone whose client does
/// not de-duplicate, and pushing again would wake every idle recipient a
/// second time, outside the debounce window that exists to stop exactly that.
///
/// Push work is handed to a detached background task, because the message is
/// already committed and its response already on the way: a relay outage can
/// never turn a successful send into an error.
///
/// Unlike reactions and polls, attachments can exist the instant a message is
/// created (they were uploaded before this call and just linked inside it), so
/// the echoed response needs its own lookup rather than staying empty the way
/// a fresh message's reactions correctly do.
async fn send(
    Authed(ctx): Authed,
    Path(channel_id): Path<String>,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<SendRequest>,
) -> Result<Json<MessageDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let attachment_ids = parse_attachment_ids(&req.attachment_ids)?;

    // ATTACH_FILES only when the send carries something; see this function's
    // note for why a missing channel and a denied one look the same.
    let mut needed = Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES);
    if !attachment_ids.is_empty() {
        needed = needed.union(Permissions::ATTACH_FILES);
    }
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, needed)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let content = validate_content(&req.content, !attachment_ids.is_empty())?;
    let id = MessageId(parse_uuid(&req.id)?);
    let sent = state
        .store
        .send_message(channel_id, ctx.user_id, id, content, &attachment_ids)
        .await?;

    // Read once and used twice: the live frame and this response need the
    // same summaries, and a fresh message can already have them.
    let attachments: Vec<_> = state
        .store
        .attachments_for_messages(&[id])
        .await?
        .into_iter()
        .next()
        .map(|(_, summaries)| summaries)
        .unwrap_or_default();

    // An idempotent retry must not fan out or push again; see the note on
    // this function.
    if sent.fresh {
        state.hub.publish(Event::MessageCreated {
            message: sent.message.clone(),
            attachments: attachments.clone(),
        });

        // Cheap in-memory decision only, real work detached; see the note on
        // this function.
        state.push.notify_message(
            state.store.clone(),
            channel_id,
            ctx.user_id,
            sent.message.id,
            sent.message.seq,
        );
    }

    let mut dto: MessageDto = sent.message.into();
    dto.attachments = attachments.into_iter().map(AttachmentDto::from).collect();
    Ok(Json(dto))
}

async fn list(
    Authed(ctx): Authed,
    Path(channel_id): Path<String>,
    Query(params): Query<ListParams>,
    State(state): State<AppState>,
) -> Result<Json<Vec<MessageDto>>, ApiError> {
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let limit = params.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT);
    let messages = state
        .store
        .list_messages(channel_id, params.before, limit)
        .await?;
    let dtos = with_reactions(&state, ctx.user_id, messages).await?;
    Ok(Json(dtos))
}

/// Soft-deletes a message. Deleting your own is allowed; deleting another's
/// needs MANAGE_MESSAGES, the same split as edit.
///
/// The row is fetched regardless of `deleted_at`, because a second delete must
/// succeed rather than 404, and telling "already gone" apart from "never
/// existed in this channel" is what makes that possible.
///
/// Freed attachment files are reclaimed best-effort and only logged on
/// failure. The database rows went in the same transaction as the soft delete
/// and the caller has already succeeded, so a leftover file is wasted disk,
/// not a correctness bug.
async fn delete(
    Authed(ctx): Authed,
    parts: Parts,
    Path((channel_id, message_id)): Path<(String, String)>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let message_id = MessageId(parse_uuid(&message_id)?);

    // Not being able to see the channel hides whether the message exists,
    // exactly like edit.
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    // Includes soft-deleted rows so a retry succeeds; see the note above.
    let message = state
        .store
        .message_including_deleted(message_id)
        .await?
        .filter(|m| m.channel_id == channel_id)
        .ok_or(ApiError::NotFound("message not found"))?;

    // Deleting your own message is allowed; deleting another's needs manage
    // rights, same split as edit.
    let is_author = message.author_id == Some(ctx.user_id);
    if !is_author
        && !state
            .store
            .has_permission(ctx.user_id, channel_id, Permissions::MANAGE_MESSAGES)
            .await?
    {
        return Err(ApiError::Forbidden);
    }

    let outcome = state.store.delete_message(message_id).await?;
    if outcome.deleted {
        state.hub.publish(Event::MessageDeleted {
            channel_id,
            message_id,
        });
        // File reclamation only, best-effort; see the note on this function.
        for hex in outcome.freed_attachments {
            if let Err(err) = state.media.delete_attachment(&hex).await {
                tracing::warn!(error = %err, attachment = %hex, "failed to delete a freed attachment file");
            }
        }
    }
    Ok(StatusCode::NO_CONTENT)
}

/// Edits a message. Rate-limited like the other writes in this module: an edit
/// re-runs the FTS5 re-index trigger, so leaving it uncapped let one account
/// churn the search index as fast as it could send requests.
async fn edit(
    Authed(ctx): Authed,
    parts: Parts,
    Path((channel_id, message_id)): Path<(String, String)>,
    State(state): State<AppState>,
    Json(req): Json<EditRequest>,
) -> Result<Json<MessageDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    let message_id = MessageId(parse_uuid(&message_id)?);

    // Not being able to see the channel hides whether the message exists.
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let message = state
        .store
        .message(message_id)
        .await?
        .filter(|m| m.channel_id == channel_id)
        .ok_or(ApiError::NotFound("message not found"))?;

    // Editing your own message is allowed; editing another's needs manage rights.
    let is_author = message.author_id == Some(ctx.user_id);
    if !is_author
        && !state
            .store
            .has_permission(ctx.user_id, channel_id, Permissions::MANAGE_MESSAGES)
            .await?
    {
        return Err(ApiError::Forbidden);
    }

    // An edit carries no attachment list, so it can never be the case that a
    // file is left standing in for the text being cleared.
    let content = validate_content(&req.content, false)?;
    let updated = state
        .store
        .edit_message(message_id, content)
        .await?
        .ok_or(ApiError::NotFound("message not found"))?;
    state.hub.publish(Event::MessageEdited(updated.clone()));
    Ok(Json(updated.into()))
}

// --- Shared enrichment ---

/// Batch-attaches each message's reaction summary and, if it carries one,
/// its poll, to its DTO - in a fixed small number of queries rather than one
/// per row, which only bites once a channel has real traffic. Shared by
/// [`list`], the full-text search route, sync, and the pinned-message list,
/// which all enrich a page of messages the same way.
pub(crate) async fn with_reactions(
    state: &AppState,
    viewer: UserId,
    messages: Vec<Message>,
) -> anyhow::Result<Vec<MessageDto>> {
    let ids: Vec<MessageId> = messages.iter().map(|m| m.id).collect();
    let mut by_message = state.store.reactions_for_messages(&ids, viewer).await?;
    let mut attachments_by_message = state.store.attachments_for_messages(&ids).await?;

    let mut dtos: Vec<MessageDto> = Vec::with_capacity(messages.len());
    for message in messages {
        let id = message.id;
        let mut dto = MessageDto::from(message);
        if let Some(pos) = by_message.iter().position(|(mid, _)| *mid == id) {
            let (_, summaries) = by_message.swap_remove(pos);
            dto.reactions = summaries
                .into_iter()
                .map(|s| ReactionDto {
                    emoji: s.emoji,
                    count: s.count,
                    reacted: s.reacted,
                })
                .collect();
        }
        if let Some(pos) = attachments_by_message
            .iter()
            .position(|(mid, _)| *mid == id)
        {
            let (_, summaries) = attachments_by_message.swap_remove(pos);
            dto.attachments = summaries.into_iter().map(AttachmentDto::from).collect();
        }
        dtos.push(dto);
    }
    // `attach_polls` pairs the two lists positionally, which holds because the
    // loop above pushes exactly one `dtos` entry per `ids` entry.
    super::polls::attach_polls(state, viewer, &ids, &mut dtos).await?;
    Ok(dtos)
}

// --- Validation ---

/// Bounds a message's text. [`empty_ok`] is set by a send that carries
/// attachments, where the file is the message and the text is genuinely
/// optional; every other caller passes false, so the relaxation cannot spread
/// by being the default.
fn validate_content(content: &str, empty_ok: bool) -> Result<&str, ApiError> {
    if !empty_ok && content.trim().is_empty() {
        return Err(ApiError::BadRequest("message content must not be empty"));
    }
    if content.chars().count() > MESSAGE_MAX_CHARS {
        return Err(ApiError::BadRequest("message content is too long"));
    }
    Ok(content)
}

/// Parses and bounds a send's attachment id list. Each id must be a
/// well-formed 32-byte sha256 in hex; whether it actually names something
/// uploaded is checked later, inside the same transaction as the insert
/// ([`crate::store::Store::send_message`]).
fn parse_attachment_ids(raw: &[String]) -> Result<Vec<Vec<u8>>, ApiError> {
    if raw.len() > MAX_ATTACHMENTS_PER_MESSAGE {
        return Err(ApiError::BadRequest("too many attachments"));
    }
    raw.iter()
        .map(|s| {
            media::from_hex(s)
                .filter(|bytes| bytes.len() == 32)
                .ok_or(ApiError::BadRequest("invalid attachment id"))
        })
        .collect()
}

pub(crate) fn parse_uuid(value: &str) -> Result<Uuid, ApiError> {
    Uuid::parse_str(value).map_err(|_| ApiError::BadRequest("invalid uuid"))
}
