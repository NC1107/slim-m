// SPDX-License-Identifier: AGPL-3.0-only
//! One pass over the whole documented surface, in dependency order: claim the
//! deployment, invite a second account, then build the channel, message,
//! attachment, poll, pin and reaction state each later call needs.
//!
//! Ordering is not incidental. Reactions, an attachment and a poll are all in
//! place before `listMessages` and `sync` run, so the `Message` shape those
//! two validate is the fully populated one rather than a bare text row; and
//! the account-destroying calls (`logout`, `deleteAccount`, `resetPassword`)
//! run last, against accounts nothing else still needs.

use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde_json::{Value, json};
use uuid::Uuid;

use super::world::{Contract, Payload};

mod content;
mod people;

use content::{channel_calls, message_calls};
use people::{moderation_calls, profile_calls, safety_calls};

const PASSWORD: &str = "a-long-enough-password";
/// A PNG header is all the server's content sniffing looks at.
pub(super) const PNG: [u8; 12] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4];
pub(super) const THUMBS_UP: &str = "%F0%9F%91%8D";

pub(super) fn text(value: &Value, field: &str) -> String {
    value[field]
        .as_str()
        .unwrap_or_else(|| panic!("expected a string `{field}` in {value}"))
        .to_owned()
}

fn signup(username: &str, device: &str, invite: Option<&str>) -> Value {
    json!({
        "username": username,
        "display_name": username,
        "password": PASSWORD,
        "device_name": device,
        "invite_code": invite,
    })
}

pub async fn run(c: &mut Contract) {
    c.call("getHealth", "GET", "/healthz", None, Payload::None)
        .await;
    c.call("getVersion", "GET", "/version", None, Payload::None)
        .await;

    // The first account through registration claims the deployment and is its
    // administrator, so everything below that needs a privilege has one.
    let admin = c
        .call(
            "register",
            "POST",
            "/auth/register",
            None,
            Payload::Json(signup("admin", "laptop", None)),
        )
        .await;
    let admin_token = text(&admin, "access_token");
    let root = admin_token.as_str();
    let admin_id = text(&admin, "user_id");

    let invite = c
        .json(
            "createInvite",
            "POST",
            "/invites",
            root,
            json!({ "max_uses": 5 }),
        )
        .await;
    let code = text(&invite, "code");
    c.get("listInvites", "/invites", root).await;
    c.call(
        "checkInvite",
        "GET",
        &format!("/invites/{code}/check"),
        None,
        Payload::None,
    )
    .await;

    let bob = c
        .call(
            "register",
            "POST",
            "/auth/register",
            None,
            Payload::Json(signup("bob", "phone", Some(&code))),
        )
        .await;
    let bob_access = text(&bob, "access_token");
    let bob_token = bob_access.as_str();
    let bob_id = text(&bob, "user_id");

    let second = c
        .call(
            "login",
            "POST",
            "/auth/login",
            None,
            Payload::Json(json!({
                "username": "bob", "password": PASSWORD, "device_name": "tablet"
            })),
        )
        .await;
    c.call(
        "refresh",
        "POST",
        "/auth/refresh",
        None,
        Payload::Json(json!({ "refresh_token": text(&second, "refresh_token") })),
    )
    .await;
    c.bare("createWsTicket", "POST", "/auth/ws-ticket", root)
        .await;

    profile_calls(c, root, &admin_id, &bob_id).await;
    safety_calls(c, root, bob_token, &bob_id).await;

    let channel = channel_calls(c, root, &bob_id).await;
    let message = message_calls(c, root, &channel).await;
    moderation_calls(c, root, bob_token, &message).await;

    c.json(
        "sync",
        "POST",
        "/sync",
        root,
        json!({ "scopes": [{ "channel_id": channel, "after_seq": 0 }] }),
    )
    .await;
    c.bare(
        "mintVoiceToken",
        "POST",
        &format!("/channels/{channel}/voice/token"),
        root,
    )
    .await;

    push_calls(c, root).await;
    invite_calls(c, root, bob_token).await;
    farewell_calls(c, root, &bob_id, &code, &channel).await;
}

async fn push_calls(c: &mut Contract, root: &str) {
    c.json(
        "registerPush",
        "PUT",
        "/push",
        root,
        json!({
            "platform": "ios",
            "push_token": "a-device-token",
            "voip_push_token": "a-voip-token",
            "push_public_key": BASE64.encode([7u8; 32]),
        }),
    )
    .await;
    c.json(
        "reportPushLifecycle",
        "PUT",
        "/push/lifecycle",
        root,
        json!({ "state": "background" }),
    )
    .await;
    c.bare("deregisterPush", "DELETE", "/push", root).await;
}

/// A second, unlimited code, so redeeming and revoking it cannot spend or
/// close the one the remaining registrations below still need. Checking this
/// one as well as the capped one above is what puts a null through the
/// optional halves of the invite preview.
async fn invite_calls(c: &mut Contract, root: &str, bob_token: &str) {
    let spare = c
        .json("createInvite", "POST", "/invites", root, json!({}))
        .await;
    let spare = text(&spare, "code");
    c.call(
        "checkInvite",
        "GET",
        &format!("/invites/{spare}/check"),
        None,
        Payload::None,
    )
    .await;
    c.bare(
        "redeemInvite",
        "POST",
        &format!("/invites/{spare}/redeem"),
        bob_token,
    )
    .await;
    c.bare("revokeInvite", "DELETE", &format!("/invites/{spare}"), root)
        .await;
}

/// The calls that end a session or an account, on throwaway accounts so
/// nothing above depends on what they destroy. `resetPassword` is last of all
/// because it revokes every session the account it recovers still holds.
async fn farewell_calls(c: &mut Contract, root: &str, bob_id: &str, code: &str, channel: &str) {
    let carol = c
        .call(
            "register",
            "POST",
            "/auth/register",
            None,
            Payload::Json(signup("carol", "desktop", Some(code))),
        )
        .await;
    c.bare(
        "logout",
        "POST",
        "/auth/logout",
        &text(&carol, "access_token"),
    )
    .await;

    // Dave writes before he leaves, so the listing afterwards carries the
    // anonymized author shape the schema documents and nothing else here
    // would ever produce.
    let dave = c
        .call(
            "register",
            "POST",
            "/auth/register",
            None,
            Payload::Json(signup("dave", "desktop", Some(code))),
        )
        .await;
    let dave_token = text(&dave, "access_token");
    let messages = format!("/channels/{channel}/messages");
    c.json(
        "sendMessage",
        "POST",
        &messages,
        &dave_token,
        json!({ "id": Uuid::now_v7().to_string(), "content": "written before leaving" }),
    )
    .await;
    c.bare("deleteAccount", "DELETE", "/account", &dave_token)
        .await;
    c.get("listMessages", &format!("{messages}?limit=50"), root)
        .await;

    let issued = c
        .bare(
            "issueResetCode",
            "POST",
            &format!("/admin/users/{bob_id}/reset-code"),
            root,
        )
        .await;
    c.call(
        "resetPassword",
        "POST",
        "/auth/reset",
        None,
        Payload::Json(json!({
            "code": text(&issued, "code"),
            "new_password": "an-entirely-new-password",
        })),
    )
    .await;
}
