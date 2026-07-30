// SPDX-License-Identifier: AGPL-3.0-only
//! Full-text search over one channel's live messages, backed by the FTS5
//! index kept current by the triggers in migration 0002.
//!
//! `q` reaches FTS5 close to as-is, so a caller may use its mini query
//! language (`AND`/`OR`/`NOT`, `"phrase"`, a trailing `*` prefix). That is
//! safe against leaking another channel: the index has exactly one column
//! (`content`), so a query string has no other column to pivot to, and the
//! channel restriction is an ordinary SQL predicate the query text can never
//! reach, never part of the `MATCH` expression itself. See
//! [`crate::store::Store::search_messages`] for the rest of that reasoning
//! and for how a malformed query surfaces as [`SearchError::InvalidQuery`]
//! rather than a 500: SQLite only validates FTS5 syntax once the statement
//! runs.

use axum::Router;
use axum::extract::{Path, State};
use axum::routing::get;
use serde::Deserialize;

use super::AppState;
use super::error::ApiError;
use super::extract::{AuthedLimited, Json, Query, READ};
use super::messages::{MessageDto, parse_uuid, with_reactions};
use crate::ids::ChannelId;
use crate::permissions::Permissions;
use crate::store::SearchError;

/// Longest a search query may be.
const MAX_QUERY_CHARS: usize = 200;
/// Default and maximum page sizes, matching plain message history.
const DEFAULT_LIMIT: i64 = 50;
const MAX_LIMIT: i64 = 100;

/// The search route, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new().route("/channels/{channel_id}/messages/search", get(search))
}

#[derive(Deserialize)]
struct SearchParams {
    q: String,
    before: Option<i64>,
    limit: Option<i64>,
}

/// Full-text search within one channel.
///
/// A nonexistent channel grants no permissions, so this refuses both "you
/// cannot search here" and "no such channel" identically, revealing neither,
/// exactly like listing.
async fn search(
    AuthedLimited(ctx): AuthedLimited<READ>,
    Path(channel_id): Path<String>,
    Query(params): Query<SearchParams>,
    State(state): State<AppState>,
) -> Result<Json<Vec<MessageDto>>, ApiError> {
    let channel_id = ChannelId(parse_uuid(&channel_id)?);
    // A missing channel and a denied one answer alike; see the note above.
    if !state
        .store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await?
    {
        return Err(ApiError::Forbidden);
    }

    let query = validate_query(&params.q)?;
    let limit = params.limit.unwrap_or(DEFAULT_LIMIT).clamp(1, MAX_LIMIT);

    let messages = match state
        .store
        .search_messages(channel_id, query, params.before, limit)
        .await
    {
        Ok(rows) => rows,
        Err(SearchError::InvalidQuery) => {
            return Err(ApiError::BadRequest("that search query is not valid"));
        }
        Err(SearchError::Internal(e)) => return Err(e.into()),
    };

    let dtos = with_reactions(&state, ctx.user_id, messages).await?;
    Ok(Json(dtos))
}

fn validate_query(q: &str) -> Result<&str, ApiError> {
    let trimmed = q.trim();
    if trimmed.is_empty() {
        return Err(ApiError::BadRequest("search query must not be empty"));
    }
    if trimmed.chars().count() > MAX_QUERY_CHARS {
        return Err(ApiError::BadRequest("search query is too long"));
    }
    Ok(trimmed)
}
