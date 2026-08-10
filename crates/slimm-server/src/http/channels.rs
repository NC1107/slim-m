// SPDX-License-Identifier: AGPL-3.0-only
//! Channel routes: list, create, rename, and soft-delete.
//!
//! Listing is filtered per caller, so a channel you cannot view is simply not
//! in your list. Every mutation - create, rename, delete - checks
//! MANAGE_CHANNELS at the deployment level (like [`Store::base_permissions`],
//! not [`Store::has_permission`]), which on a fresh deployment only the
//! bootstrap admin holds. A per-channel overwrite is deliberately not
//! consulted here: a channel-scoped check would make a delete of an
//! already-deleted channel indistinguishable from "no permission" (a deleted
//! channel evaluates to no permissions at all), breaking the idempotency a
//! retry needs. The base check also still hides which ids are real from
//! anyone without MANAGE_CHANNELS, which is the population that check is
//! actually protecting against; an existing channel manager is not an
//! attacker this needs to hide anything from.

use axum::Router;
use axum::extract::{DefaultBodyLimit, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{get, patch};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, AuthedLimited, Json, READ, enforce};
use super::messages::parse_uuid;
use crate::hub::Event;
use crate::ids::ChannelId;
use crate::permissions::Permissions;
use crate::ratelimit::Class;
use crate::store::{Channel, DM_CHANNEL_KIND, DeleteChannelError};

const CHANNEL_BODY_LIMIT: usize = 4 * 1024;
/// A one-line header, not a description field: long enough for a real
/// sentence, short enough that a client never needs to wrap or truncate it
/// in the channel header it's designed for.
const CHANNEL_TOPIC_MAX_CHARS: usize = 256;

/// The channel routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/channels", get(list).post(create))
        .route("/channels/{channel_id}", patch(update).delete(delete))
        .layer(DefaultBodyLimit::max(CHANNEL_BODY_LIMIT))
}

/// `pub(crate)` so `http::ws` can reuse the exact same wire shape for the
/// live `channel.created`/`channel.updated` frames, the way `MessageDto`
/// already does for messages.
#[derive(Serialize)]
pub(crate) struct ChannelDto {
    id: String,
    name: String,
    kind: String,
    /// `null` for no topic. A client shows this as a one-line description
    /// beside the channel name; absence and an empty topic are treated as
    /// the same thing, so this is never `Some("")` - see
    /// [`validate_channel_topic`].
    topic: Option<String>,
    /// Sort key among the deployment's live, non-DM channels: lower sorts
    /// first. Set via `PUT /channels/order`, deployment-wide rather than
    /// per-device. Meaningless on a DM, which never appears in this list.
    position: i64,
    /// The message this channel is a thread of, or `null` for an ordinary
    /// channel. A thread's own `kind` and permissions are never what govern
    /// it: `VIEW_CHANNEL`/`SEND_MESSAGES` here inherit the parent message's
    /// own channel, resolved live rather than copied - see
    /// docs/decisions/0005-threads.md. A thread never appears in
    /// `listChannels`; reach one through `openThread`.
    parent_message_id: Option<String>,
    /// The rail section this channel is filed under, or `null` for
    /// uncategorised - rendered as an implicit section above every named
    /// category. Decides placement only: see
    /// docs/decisions/0006-channel-categories.md. Absent on servers older
    /// than this field, which a client must treat as unknown rather than
    /// assuming uncategorised.
    category_id: Option<String>,
    created_at: i64,
    /// The caller's own effective permission bitmask in this channel,
    /// already resolved through thread and DM handling with any timeout
    /// subtracted - the batched sibling of `GET
    /// /channels/{channelId}/permissions`. Present only on `listChannels`:
    /// every row there already carries VIEW_CHANNEL by construction, so
    /// unlike the dedicated route this needs no existence-probe mask, and
    /// it costs no extra query since `Store::visible_channels_with_permissions`
    /// already computes it. Absent (not `Some(0)`) from create, update,
    /// reorder, and the live `channel.created`/`channel.updated` frames:
    /// none of those has one single caller whose bitmask would be right to
    /// embed, and a live frame in particular fans out to many receivers
    /// holding different permissions.
    #[serde(skip_serializing_if = "Option::is_none")]
    permissions: Option<i64>,
}

impl From<Channel> for ChannelDto {
    fn from(channel: Channel) -> Self {
        Self {
            id: channel.id.to_string(),
            name: channel.name,
            kind: channel.kind,
            topic: channel.topic,
            position: channel.position,
            parent_message_id: channel.parent_message_id.map(|id| id.to_string()),
            category_id: channel.category_id.map(|id| id.to_string()),
            created_at: channel.created_at,
            permissions: None,
        }
    }
}

#[derive(Deserialize)]
struct CreateRequest {
    name: String,
    /// "text" or "voice"; defaults to text.
    kind: Option<String>,
}

#[derive(Deserialize)]
struct UpdateChannelRequest {
    /// Absent leaves the name unchanged - both fields on this request are
    /// optional, the same "at least one, absent means untouched" convention
    /// `roles::UpdateRoleRequest` uses for its own two optional fields.
    #[serde(default)]
    name: Option<String>,
    /// Absent leaves the topic unchanged; present (even as an empty or
    /// whitespace-only string) replaces it, clearing it back to `None` if the
    /// trimmed value is blank - see [`validate_channel_topic`].
    #[serde(default)]
    topic: Option<String>,
}

/// Lists the channels the caller can view. One batched store call: the
/// per-channel has_permission loop this replaces cost 1 + 4C queries.
///
/// Answers a plain array, exactly as it always has: the wire is
/// additive-only, and a live deployment auto-updating from `latest` while
/// its phones update on their own TestFlight/Play schedule means reshaping
/// this response would break every client that has not updated yet. Every
/// live category is at `GET /categories` instead - a new route is additive,
/// folding the list into this one's body is not.
///
/// Each row's `permissions` rides along free: `visible_channels_with_permissions`
/// already evaluates the full bitmask to decide VIEW_CHANNEL membership, so
/// carrying it into the response is a change to what gets kept, not a new
/// query.
async fn list(
    AuthedLimited(ctx): AuthedLimited<READ>,
    State(state): State<AppState>,
) -> Result<Json<Vec<ChannelDto>>, ApiError> {
    let visible = state
        .store
        .visible_channels_with_permissions(ctx.user_id)
        .await?
        .into_iter()
        .map(|(channel, permissions)| ChannelDto {
            permissions: Some(permissions.bits()),
            ..ChannelDto::from(channel)
        })
        .collect();
    Ok(Json(visible))
}

/// Creates a channel. Requires MANAGE_CHANNELS at the deployment level.
async fn create(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
    Json(req): Json<CreateRequest>,
) -> Result<Json<ChannelDto>, ApiError> {
    // Charged like rename and delete, which both do; create was the one write
    // in this file that was not, so it could be looped without limit.
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::MANAGE_CHANNELS)
    {
        return Err(ApiError::Forbidden);
    }

    let name = validate_channel_name(&req.name)?;
    let kind = req.kind.as_deref().unwrap_or("text");
    if !matches!(kind, "text" | "voice") {
        return Err(ApiError::BadRequest("kind must be text or voice"));
    }

    let channel = state.store.create_channel(name, kind).await?;
    state.hub.publish(Event::ChannelCreated(channel.clone()));
    Ok(Json(channel.into()))
}

/// Renames a channel and/or replaces its topic. Requires MANAGE_CHANNELS at
/// the deployment level - the same gate `create` and `delete` use, not a new
/// one for the topic half of this route.
async fn update(
    Authed(ctx): Authed,
    parts: Parts,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
    Json(req): Json<UpdateChannelRequest>,
) -> Result<Json<ChannelDto>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);

    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::MANAGE_CHANNELS)
    {
        return Err(ApiError::Forbidden);
    }

    let name = req.name.as_deref().map(validate_channel_name).transpose()?;
    let topic = req
        .topic
        .as_deref()
        .map(validate_channel_topic)
        .transpose()?;
    if name.is_none() && topic.is_none() {
        return Err(ApiError::BadRequest("nothing to update"));
    }

    let channel = state
        .store
        .update_channel(channel_id, name, topic.as_ref().map(|t| t.as_deref()))
        .await?
        .ok_or(ApiError::NotFound("channel not found"))?;
    state.hub.publish(Event::ChannelUpdated(channel.clone()));
    Ok(Json(channel.into()))
}

/// Soft-deletes a channel. Requires MANAGE_CHANNELS at the deployment level.
///
/// Refuses to delete the deployment's last live channel: with zero channels
/// left nobody has anywhere to land, which is exactly why bootstrap seeds a
/// `general` channel for a fresh deployment in the first place. A second
/// delete of an already-deleted channel is not an error, matching the rest of
/// this API's delete verbs; a channel id that was never real is a plain 404,
/// same as it would be for any other resource a manager is allowed to see.
///
/// The row is fetched regardless of `deleted_at`, because telling "already
/// gone" apart from "never existed" is what makes that retry succeed.
///
/// A DM is a channel of kind `dm` in the same table, and it is not a
/// manageable channel: its only access rule is membership of the pair, which
/// this deployment-wide check knows nothing about. The store refuses it too,
/// but it can only answer "no rows matched", which this handler would report
/// as the last-channel conflict. Answering 404 here keeps the status honest
/// and matches how a DM is invisible to `GET /channels`.
async fn delete(
    Authed(ctx): Authed,
    parts: Parts,
    Path(channel_id): Path<String>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let channel_id = ChannelId(parse_uuid(&channel_id)?);

    if !state
        .store
        .base_permissions(ctx.user_id)
        .await?
        .contains(Permissions::MANAGE_CHANNELS)
    {
        return Err(ApiError::Forbidden);
    }

    // Includes soft-deleted rows so a retry succeeds; see the note above.
    let channel = state
        .store
        .channel_including_deleted(channel_id)
        .await?
        .ok_or(ApiError::NotFound("channel not found"))?;

    // 404 rather than letting the store's "no rows" surface as a conflict;
    // see the note above.
    if channel.kind == DM_CHANNEL_KIND {
        return Err(ApiError::NotFound("channel not found"));
    }

    match state.store.delete_channel(channel_id).await {
        // Only a genuine delete is worth publishing; a retry changes nothing.
        Ok(true) => {
            state.hub.publish(Event::ChannelDeleted { channel_id });
            Ok(StatusCode::NO_CONTENT)
        }
        Ok(false) => Ok(StatusCode::NO_CONTENT),
        Err(DeleteChannelError::LastChannel) => Err(ApiError::Conflict(
            "cannot delete the deployment's last channel",
        )),
        Err(DeleteChannelError::Internal(e)) => Err(e.into()),
    }
}

// --- Validation ---

/// Normalizes a topic edit. A blank (or whitespace-only) value clears the
/// topic back to `None` rather than being stored as an empty string: a topic
/// with nothing visible in it is not meaningfully different from having
/// none, and folding the two together means a single `Option<String>` field
/// can carry "clear it" without a separate tri-state signal.
fn validate_channel_topic(topic: &str) -> Result<Option<String>, ApiError> {
    let trimmed = topic.trim();
    if trimmed.chars().count() > CHANNEL_TOPIC_MAX_CHARS {
        return Err(ApiError::BadRequest("topic must be at most 256 characters"));
    }
    if trimmed.chars().any(|c| c.is_control()) {
        return Err(ApiError::BadRequest(
            "topic must not contain control characters",
        ));
    }
    Ok(if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_owned())
    })
}

fn validate_channel_name(name: &str) -> Result<&str, ApiError> {
    let trimmed = name.trim();
    if trimmed.is_empty() || trimmed.chars().count() > 64 {
        return Err(ApiError::BadRequest("name must be 1 to 64 characters"));
    }
    if trimmed.chars().any(|c| c.is_control()) {
        return Err(ApiError::BadRequest(
            "name must not contain control characters",
        ));
    }
    Ok(trimmed)
}
