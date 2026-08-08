// SPDX-License-Identifier: AGPL-3.0-only
//! Canvas media-slot calls for `content.rs`'s own `channel_calls`, a sibling
//! module rather than folded into that already near-the-limit function -
//! `content.rs` was 505 lines with this inline, over the 500-line hard cap.

use serde_json::json;

use crate::world::Contract;

/// Named for bob, not root, so this also exercises the no-own-tile gate:
/// anyone with USE_CANVAS may arrange anyone's media slot.
pub(super) async fn media_slot_calls(c: &mut Contract, root: &str, channel: &str, bob_id: &str) {
    c.json(
        "putCanvasMediaSlot",
        "PUT",
        &format!("/channels/{channel}/canvas/media-slots/screen/{bob_id}"),
        root,
        json!({
            "x": 40.0, "y": 40.0, "w": 360.0, "h": 203.0,
            "locked": false, "sent_to_back": false,
        }),
    )
    .await;
    c.get(
        "listCanvasMediaSlots",
        &format!("/channels/{channel}/canvas/media-slots"),
        root,
    )
    .await;
}
