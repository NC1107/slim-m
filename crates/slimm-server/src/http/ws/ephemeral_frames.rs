// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Authorizing a bot's private message for one connection, split out of
//! [`super::authorization::authorize`] to keep that file's match focused.

use super::authorization::Authorization;
use super::frames::ServerFrame;
use crate::ephemeral::EphemeralMessage;
use crate::http::ephemeral_messages::EphemeralMessageDto;
use crate::ids::UserId;
use crate::permissions::Permissions;
use crate::store::{SessionContext, Store};

/// Delivered to the recipient's own connections only, and only while they can
/// still view the channel and have not blocked the sender. Any store error
/// withholds: a private message must fail closed, and it has no catch-up path.
pub(super) async fn authorize(
    store: &Store,
    ctx: &SessionContext,
    recipient_id: UserId,
    message: &EphemeralMessage,
) -> Authorization {
    if recipient_id != ctx.user_id {
        return Authorization::Withhold;
    }
    let can_view = matches!(
        store
            .has_permission(ctx.user_id, message.channel_id, Permissions::VIEW_CHANNEL)
            .await,
        Ok(true)
    );
    let blocked = !matches!(
        store.has_blocked(ctx.user_id, message.author_id).await,
        Ok(false)
    );
    if !can_view || blocked {
        return Authorization::Withhold;
    }
    Authorization::Deliver(Box::new(ServerFrame::MessageEphemeral {
        channel_id: message.channel_id.to_string(),
        message: EphemeralMessageDto::from(message),
    }))
}
