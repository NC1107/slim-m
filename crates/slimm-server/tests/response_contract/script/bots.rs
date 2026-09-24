// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Bot provisioning and command registration, in call order: create, list,
//! register commands as the bot itself, read them back both ways, revoke.
//!
//! Order matters for the same reason it does in `read_state.rs`. `listBots`
//! runs after `createBot` so its answer is a non-empty list, which is the only
//! version of that response worth validating - an empty array would satisfy the
//! schema while proving nothing about the fields. `setBotCommands` has to run
//! before `revokeBot`, since a revoked bot's own token can no longer call
//! anything; `listChannelBotCommands` runs while the registration is still
//! live so its answer is non-empty too. `revokeBot` runs last because it
//! needs a bot to revoke.
//!
//! Runs near the end of the script, after the member-facing cases, because
//! creating a bot adds a member and nothing earlier should have to account for
//! it.

use serde_json::json;

use crate::world::Contract;

use super::text;

pub(crate) async fn bot_calls(c: &mut Contract, root: &str, channel: &str) {
    let created = c
        .json(
            "createBot",
            "POST",
            "/bots",
            root,
            json!({ "username": "helper-bot", "display_name": "Helper" }),
        )
        .await;
    c.get("listBots", "/bots", root).await;

    let bot_id = text(&created["bot"], "user_id");
    let bot_token = text(&created, "token");

    c.json(
        "setBotCommands",
        "PUT",
        "/bots/commands",
        &bot_token,
        json!({
            "prefix": "!",
            "commands": [{ "name": "ping", "description": "check if I'm alive" }]
        }),
    )
    .await;
    c.get("getBotCommands", &format!("/bots/{bot_id}/commands"), root)
        .await;
    c.get(
        "listChannelBotCommands",
        &format!("/channels/{channel}/bot-commands"),
        root,
    )
    .await;

    c.bare("revokeBot", "POST", &format!("/bots/{bot_id}/revoke"), root)
        .await;
}
