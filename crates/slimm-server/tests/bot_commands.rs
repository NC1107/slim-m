// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Bot command registration: `PUT /bots/commands`, `GET /bots/{botId}/commands`
//! and `GET /channels/{channelId}/bot-commands`. See
//! docs/decisions/0031-bot-command-registration.md.
//!
//! Registration itself (who may call it, the bulk-overwrite shape, the caps)
//! is one set of cases; what the composer's discovery list is allowed to
//! leak is another. The two that matter most are the ones a regression would
//! not otherwise be caught by: a revoked or Space-removed bot's commands
//! must vanish from discovery with no separate cleanup path, and a bot with
//! no view of a channel must not advertise itself there.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::ids::{ChannelId, RoleId, UserId};
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;

mod support;

async fn new_store(name: &str) -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new(name);
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool), guard)
}

fn app(store: Store) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
        media: slimm_server::media::Media::for_tests(),
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
        link_previews: slimm_server::http::link_preview::LinkPreviews::disabled(),
        dock: slimm_server::http::dock::Dock::disabled(),
        code_runner: slimm_server::code_runner::CodeRunner::disabled(),
    })
}

fn request(method: &str, uri: &str, token: &str, body: Option<Value>) -> Request<Body> {
    let builder = Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"));
    match body {
        Some(value) => builder
            .header("content-type", "application/json")
            .body(Body::from(value.to_string()))
            .unwrap(),
        None => builder.body(Body::empty()).unwrap(),
    }
}

async fn json_body(response: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap_or(Value::Null)
}

/// The first call claims the deployment: administrator, `@everyone` seeded
/// with VIEW_CHANNEL/SEND_MESSAGES, and a `general` channel.
async fn register(store: &Store, username: &str) -> (UserId, String) {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    let token = store
        .open_session(account.id, "cli")
        .await
        .unwrap()
        .access_token;
    (account.id, token)
}

async fn general_channel_id(store: &Store) -> ChannelId {
    store
        .list_channels()
        .await
        .unwrap()
        .into_iter()
        .next()
        .expect("bootstrap seeds a general channel")
        .id
}

async fn everyone_role_id(store: &Store) -> RoleId {
    RoleId(
        store
            .list_roles()
            .await
            .unwrap()
            .into_iter()
            .find(|r| r.is_everyone)
            .expect("bootstrap seeds @everyone")
            .id
            .0,
    )
}

/// A fresh bot, holding only whatever `@everyone` holds - decision 0028's own
/// baseline.
async fn bot(store: &Store, created_by: UserId, username: &str) -> (UserId, String) {
    let new_bot = store
        .create_bot(username, username, created_by)
        .await
        .unwrap();
    (new_bot.bot.user_id, new_bot.token)
}

fn register_body(prefix: &str, commands: Value) -> Value {
    json!({ "prefix": prefix, "commands": commands })
}

#[tokio::test]
async fn a_bot_with_no_registration_answers_empty_on_its_profile_route() {
    let (store, _guard) = new_store("slimm-botcmds-none").await;
    let (admin_id, _admin_token) = register(&store, "root").await;
    let (bot_id, _bot_token) = bot(&store, admin_id, "helper").await;
    let router = app(store);

    let response = router
        .clone()
        .oneshot(request(
            "GET",
            &format!("/bots/{bot_id}/commands"),
            &_admin_token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        json_body(response).await,
        json!({ "prefix": null, "commands": [] })
    );
}

#[tokio::test]
async fn a_bot_can_register_and_read_back_its_own_commands() {
    let (store, _guard) = new_store("slimm-botcmds-register").await;
    let (admin_id, admin_token) = register(&store, "root").await;
    let (bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let router = app(store);

    let response = router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([
                    { "name": "ping", "description": "check if I'm alive" },
                    { "name": "roll", "description": "roll dice", "usage": "<sides>" }
                ]),
            )),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);

    let response = router
        .oneshot(request(
            "GET",
            &format!("/bots/{bot_id}/commands"),
            &admin_token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(
        json_body(response).await,
        json!({
            "prefix": "!",
            "commands": [
                { "name": "ping", "description": "check if I'm alive" },
                { "name": "roll", "description": "roll dice", "usage": "<sides>" }
            ]
        })
    );
}

#[tokio::test]
async fn registering_again_replaces_the_whole_set() {
    let (store, _guard) = new_store("slimm-botcmds-overwrite").await;
    let (admin_id, admin_token) = register(&store, "root").await;
    let (bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let router = app(store);

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([{ "name": "old", "description": "the old one" }]),
            )),
        ))
        .await
        .unwrap();

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "?",
                json!([{ "name": "new", "description": "the new one" }]),
            )),
        ))
        .await
        .unwrap();

    let response = router
        .oneshot(request(
            "GET",
            &format!("/bots/{bot_id}/commands"),
            &admin_token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(
        json_body(response).await,
        json!({
            "prefix": "?",
            "commands": [{ "name": "new", "description": "the new one" }]
        }),
        "the old prefix and command must be gone, not merged with the new set"
    );
}

#[tokio::test]
async fn a_human_cannot_register_bot_commands() {
    let (store, _guard) = new_store("slimm-botcmds-human").await;
    let (_admin_id, admin_token) = register(&store, "root").await;
    let router = app(store);

    let response = router
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &admin_token,
            Some(register_body("!", json!([]))),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn a_reserved_prefix_is_rejected() {
    let (store, _guard) = new_store("slimm-botcmds-reserved-prefix").await;
    let (admin_id, _admin_token) = register(&store, "root").await;
    let (_bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let router = app(store);

    for reserved in ["/", "@", ":"] {
        let response = router
            .clone()
            .oneshot(request(
                "PUT",
                "/bots/commands",
                &bot_token,
                Some(register_body(reserved, json!([]))),
            ))
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            StatusCode::BAD_REQUEST,
            "{reserved:?} already means something to the composer"
        );
    }
}

#[tokio::test]
async fn a_whitespace_prefix_is_rejected() {
    let (store, _guard) = new_store("slimm-botcmds-space-prefix").await;
    let (admin_id, _admin_token) = register(&store, "root").await;
    let (_bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let router = app(store);

    let response = router
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body("go ", json!([]))),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn a_duplicate_command_name_is_rejected_case_insensitively() {
    let (store, _guard) = new_store("slimm-botcmds-dup").await;
    let (admin_id, _admin_token) = register(&store, "root").await;
    let (_bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let router = app(store);

    let response = router
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([
                    { "name": "ping", "description": "one" },
                    { "name": "PING", "description": "two" }
                ]),
            )),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn more_than_the_cap_is_rejected_and_the_old_set_survives() {
    let (store, _guard) = new_store("slimm-botcmds-cap").await;
    let (admin_id, admin_token) = register(&store, "root").await;
    let (bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let router = app(store);

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([{ "name": "keep", "description": "still here" }]),
            )),
        ))
        .await
        .unwrap();

    let too_many: Vec<Value> = (0..51)
        .map(|i| json!({ "name": format!("cmd{i}"), "description": "d" }))
        .collect();
    let response = router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body("!", json!(too_many))),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);

    let response = router
        .oneshot(request(
            "GET",
            &format!("/bots/{bot_id}/commands"),
            &admin_token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(
        json_body(response).await["commands"],
        json!([{ "name": "keep", "description": "still here" }]),
        "a rejected bulk overwrite must not partially apply"
    );
}

#[tokio::test]
async fn an_invalid_permission_bit_is_rejected() {
    let (store, _guard) = new_store("slimm-botcmds-badbit").await;
    let (admin_id, _admin_token) = register(&store, "root").await;
    let (_bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let router = app(store);

    // 3 sets two bits at once, never a single permission.
    let response = router
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([{ "name": "ban", "description": "d", "permission": 3 }]),
            )),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

async fn channel_commands(app: &Router, channel_id: ChannelId, token: &str) -> Value {
    let response = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/channels/{channel_id}/bot-commands"),
            token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    json_body(response).await
}

#[tokio::test]
async fn a_registered_command_is_offered_in_a_channel_the_bot_can_see() {
    let (store, _guard) = new_store("slimm-botcmds-visible").await;
    let (admin_id, admin_token) = register(&store, "root").await;
    let (bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let channel = general_channel_id(&store).await;
    let router = app(store);

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([{ "name": "ping", "description": "check if I'm alive" }]),
            )),
        ))
        .await
        .unwrap();

    let commands = channel_commands(&router, channel, &admin_token).await;
    assert_eq!(
        commands,
        json!([{
            "bot_user_id": bot_id.to_string(),
            "bot_username": "helper",
            "bot_display_name": "helper",
            "prefix": "!",
            "name": "ping",
            "description": "check if I'm alive"
        }])
    );
}

/// Requirement 4 of the brief: a bot with no view of a channel must not
/// advertise itself there, even though it holds a live token and is a member
/// of the Space.
#[tokio::test]
async fn a_bot_with_no_view_of_the_channel_does_not_advertise_there() {
    let (store, _guard) = new_store("slimm-botcmds-no-view").await;
    let (admin_id, admin_token) = register(&store, "root").await;
    let (_bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let hidden = store.create_channel("hidden", "text").await.unwrap();
    let everyone = everyone_role_id(&store).await;
    store
        .set_role_overwrite(
            hidden.id,
            everyone,
            Permissions::NONE,
            Permissions::VIEW_CHANNEL,
        )
        .await
        .unwrap();
    let router = app(store);

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([{ "name": "ping", "description": "d" }]),
            )),
        ))
        .await
        .unwrap();

    let commands = channel_commands(&router, hidden.id, &admin_token).await;
    assert_eq!(
        commands,
        json!([]),
        "the bot itself only holds @everyone here, which this channel denies VIEW_CHANNEL to"
    );
}

/// The mutation-critical case: revoking a bot's token must make its commands
/// vanish from discovery immediately, with no separate cleanup step.
#[tokio::test]
async fn a_revoked_bots_commands_vanish_from_discovery() {
    let (store, _guard) = new_store("slimm-botcmds-revoked").await;
    let (admin_id, admin_token) = register(&store, "root").await;
    let (bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let channel = general_channel_id(&store).await;
    let router = app(store.clone());

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([{ "name": "ping", "description": "d" }]),
            )),
        ))
        .await
        .unwrap();
    assert_ne!(
        channel_commands(&router, channel, &admin_token).await,
        json!([])
    );

    store.revoke_bot(bot_id).await.unwrap();

    assert_eq!(
        channel_commands(&router, channel, &admin_token).await,
        json!([]),
        "a revoked bot's commands must disappear immediately"
    );
}

/// The other mutation-critical case: removing a bot from the Space (kicking
/// it) must also make its commands vanish, independently of revocation.
#[tokio::test]
async fn a_bot_removed_from_the_space_no_longer_advertises() {
    let (store, _guard) = new_store("slimm-botcmds-removed").await;
    let (admin_id, admin_token) = register(&store, "root").await;
    let (bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let channel = general_channel_id(&store).await;
    let router = app(store.clone());

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([{ "name": "ping", "description": "d" }]),
            )),
        ))
        .await
        .unwrap();
    assert_ne!(
        channel_commands(&router, channel, &admin_token).await,
        json!([])
    );

    store
        .remove_from_space(bot_id, admin_id, Some("no longer needed"))
        .await
        .unwrap();

    assert_eq!(
        channel_commands(&router, channel, &admin_token).await,
        json!([]),
        "a bot removed from the Space must not keep advertising commands"
    );
}

#[tokio::test]
async fn a_gated_command_is_hidden_from_a_caller_without_the_permission() {
    let (store, _guard) = new_store("slimm-botcmds-gated").await;
    let (admin_id, admin_token) = register(&store, "root").await;
    let (bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let channel = general_channel_id(&store).await;
    let plain = store.create_user("mallory", "Mallory").await.unwrap();
    let plain_token = store
        .open_session(plain.id, "phone")
        .await
        .unwrap()
        .access_token;
    let router = app(store.clone());

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([
                    { "name": "ping", "description": "open to everyone" },
                    {
                        "name": "purge",
                        "description": "gated",
                        "permission": Permissions::MANAGE_MESSAGES.bits()
                    }
                ]),
            )),
        ))
        .await
        .unwrap();

    let admin_view = channel_commands(&router, channel, &admin_token).await;
    let names: Vec<&str> = admin_view
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["name"].as_str().unwrap())
        .collect();
    assert!(names.contains(&"ping"));
    assert!(
        names.contains(&"purge"),
        "the administrator's own MANAGE_MESSAGES should still show the gated command"
    );

    let plain_view = channel_commands(&router, channel, &plain_token).await;
    let names: Vec<&str> = plain_view
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c["name"].as_str().unwrap())
        .collect();
    assert!(names.contains(&"ping"), "the ungated command stays offered");
    assert!(
        !names.contains(&"purge"),
        "a caller without MANAGE_MESSAGES must not be offered the gated command"
    );
    let _ = bot_id;
}

/// The masking rule `GET /channels/{id}/permissions` already establishes:
/// a caller who cannot view the channel at all must not learn anything
/// about it, including an otherwise-ungated bot command living there.
#[tokio::test]
async fn a_caller_without_view_channel_sees_no_commands() {
    let (store, _guard) = new_store("slimm-botcmds-caller-blind").await;
    let (admin_id, _admin_token) = register(&store, "root").await;
    let (_bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let outsider = store.create_user("outsider", "Outsider").await.unwrap();
    let outsider_token = store
        .open_session(outsider.id, "phone")
        .await
        .unwrap()
        .access_token;
    let hidden = store.create_channel("hidden", "text").await.unwrap();
    let everyone = everyone_role_id(&store).await;
    store
        .set_role_overwrite(
            hidden.id,
            everyone,
            Permissions::NONE,
            Permissions::VIEW_CHANNEL,
        )
        .await
        .unwrap();
    let router = app(store.clone());

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([{ "name": "ping", "description": "d" }]),
            )),
        ))
        .await
        .unwrap();

    assert_eq!(
        channel_commands(&router, hidden.id, &outsider_token).await,
        json!([])
    );
}

/// `account_deletion_coverage.rs` requires a recorded decision for every
/// column that references `users`; this is the behavioural half it
/// deliberately does not check itself - that the purge actually happens.
/// Without it, a deleted bot's registration would sit in `bot_commands`
/// forever, since `Store::bot_commands` never joins `users` at all and so
/// never notices the account is gone.
#[tokio::test]
async fn deleting_a_bots_account_purges_its_registration() {
    let (store, _guard) = new_store("slimm-botcmds-account-deleted").await;
    let (admin_id, admin_token) = register(&store, "root").await;
    let (bot_id, bot_token) = bot(&store, admin_id, "helper").await;
    let router = app(store.clone());

    router
        .clone()
        .oneshot(request(
            "PUT",
            "/bots/commands",
            &bot_token,
            Some(register_body(
                "!",
                json!([{ "name": "ping", "description": "d" }]),
            )),
        ))
        .await
        .unwrap();

    store.delete_account(bot_id).await.unwrap();

    let response = router
        .oneshot(request(
            "GET",
            &format!("/bots/{bot_id}/commands"),
            &admin_token,
            None,
        ))
        .await
        .unwrap();
    assert_eq!(
        json_body(response).await,
        json!({ "prefix": null, "commands": [] }),
        "a deleted bot's registration must be purged, not merely masked"
    );
}
