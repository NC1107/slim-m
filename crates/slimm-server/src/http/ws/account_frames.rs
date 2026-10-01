// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Frames private to one account: its read marker and its per-channel
//! notification overrides, delivered only to that account's own connections.

use super::authorization::Authorization;
use super::frames::ServerFrame;
use crate::hub::Event;
use crate::store::SessionContext;

/// `None` when `event` is not account-scoped. Decided before any channel
/// permission is consulted: the owner is the only audience, and everyone else
/// is withheld.
pub(super) fn authorize(ctx: &SessionContext, event: &Event) -> Option<Authorization> {
    let (owner, frame) = match event {
        Event::ReadStateChanged {
            user_id,
            channel_id,
            last_read_seq,
            manually_unread,
        } => (
            *user_id,
            ServerFrame::ReadStateChanged {
                channel_id: channel_id.to_string(),
                last_read_seq: *last_read_seq,
                manually_unread: *manually_unread,
            },
        ),
        Event::NotificationOverrideChanged {
            user_id,
            channel_id,
            preference,
        } => (
            *user_id,
            ServerFrame::NotificationOverrideChanged {
                channel_id: channel_id.to_string(),
                preference: preference.map(|p| p.as_str().to_owned()),
            },
        ),
        _ => return None,
    };
    Some(if owner == ctx.user_id {
        Authorization::Deliver(Box::new(frame))
    } else {
        Authorization::Withhold
    })
}
