// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The GIF proxy's four documented calls, in the order they depend on each
//! other: a search mints the opaque token every later call is keyed on, the
//! preview fetches through it, and select turns it into a real attachment.
//!
//! Trending takes no token and could run anywhere, but sits here so the whole
//! provider surface is validated in one place rather than split across this
//! pass by whether a call happens to need state.
//!
//! Every one of these reaches a real 2xx because the pass runs against a fake
//! local provider rather than Tenor or Klipy; see `world.rs`.

use serde_json::json;

use super::text;
use crate::world::Contract;

pub(super) async fn gif_calls(c: &mut Contract, root: &str) {
    let search = c
        .bare("searchGifs", "GET", "/gifs/search?q=cat", root)
        .await;
    let id = text(&search["results"][0], "id");
    c.bare("getGifPreview", "GET", &format!("/gifs/preview/{id}"), root)
        .await;
    c.json(
        "selectGif",
        "POST",
        "/gifs/select",
        root,
        json!({ "id": id }),
    )
    .await;
    c.bare("getTrendingGifs", "GET", "/gifs/trending", root)
        .await;
}
