// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Reporting a bot's private message, which nothing stored: the reporter's
//! own client supplies the text, and the queue says so.
//! See docs/decisions/0037-ephemeral-bot-messages.md.

use super::error::ApiError;
use super::messages::parse_uuid;
use crate::ids::{ChannelId, MessageId, UserId};
use crate::permissions::Permissions;
use crate::store::EphemeralSubject;

/// The longest snapshot a report may carry, matching a message's own cap.
const SNAPSHOT_MAX_CHARS: usize = 4000;

/// What the reporter's client says it showed them, as it arrived on the wire.
pub(super) struct Claim<'a> {
    pub message_id: &'a str,
    pub channel_id: Option<&'a str>,
    pub author_id: Option<&'a str>,
    pub snapshot: Option<&'a str>,
}

/// A claim that parsed and whose snapshot is within bounds.
pub(super) struct Parsed {
    pub message_id: MessageId,
    pub channel_id: ChannelId,
    pub author_id: UserId,
    pub snapshot: String,
}

impl Parsed {
    pub(super) fn subject(&self) -> EphemeralSubject<'_> {
        EphemeralSubject {
            message_id: self.message_id,
            channel_id: self.channel_id,
            author_id: self.author_id,
            snapshot: &self.snapshot,
        }
    }
}

pub(super) fn parse(claim: &Claim<'_>) -> Result<Parsed, ApiError> {
    let missing = ApiError::BadRequest("channel_id, author_id and snapshot are required");
    let (Some(channel), Some(author), Some(snapshot)) =
        (claim.channel_id, claim.author_id, claim.snapshot)
    else {
        return Err(missing);
    };
    let snapshot = snapshot.trim();
    if snapshot.is_empty() {
        return Err(ApiError::BadRequest("snapshot must not be empty"));
    }
    if snapshot.chars().count() > SNAPSHOT_MAX_CHARS {
        return Err(ApiError::BadRequest("snapshot is too long"));
    }
    Ok(Parsed {
        message_id: MessageId(parse_uuid(claim.message_id)?),
        channel_id: ChannelId(parse_uuid(channel)?),
        author_id: UserId(parse_uuid(author)?),
        snapshot: snapshot.to_owned(),
    })
}

/// The reporter must be able to see the channel and the named author must be
/// a bot, or the report would name nobody a bot could have written to.
pub(super) async fn authorize(
    state: &super::AppState,
    reporter: UserId,
    claim: &Parsed,
) -> Result<(), ApiError> {
    let can_view = state
        .store
        .has_permission(reporter, claim.channel_id, Permissions::VIEW_CHANNEL)
        .await?;
    if !can_view || !state.store.is_bot(claim.author_id).await? {
        return Err(ApiError::NotFound("that message was not found"));
    }
    Ok(())
}
