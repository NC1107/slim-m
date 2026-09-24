// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Bot provisioning, command registration and permissioning, in call order:
//! create, list, register commands as the bot itself, read both ways,
//! repermission, revoke - order matters since a revoked token can no longer
//! call `setBotCommands`, and `setBotPermissions`/`revokeBot` both need a
//! live bot.
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

    c.json(
        "setBotPermissions",
        "PATCH",
        &format!("/bots/{bot_id}/permissions"),
        root,
        json!({ "permissions": 0 }),
    )
    .await;
    c.bare("revokeBot", "POST", &format!("/bots/{bot_id}/revoke"), root)
        .await;
}
