// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Read-side enrichment for `message_embeds`: stage 3 of
//! `docs/decisions/0030-incoming-webhooks.md`, store and enrichment first.
//! Nothing here posts an embed through an HTTP route yet - that is the
//! webhook delivery and bot send paths' own job - so every embed below is
//! written straight through the store, the same way a future caller's
//! validated input eventually will be, and read back through the ordinary
//! `GET /channels/{id}/messages` route to prove `http::message_enrich`
//! actually attaches what the store holds.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::Value;
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::link_preview::LinkPreviews;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::{NewEmbed, NewEmbedField, NewMessage, Store};
use tower::ServiceExt;

mod support;

struct Harness {
    app: Router,
    store: Store,
    _guard: support::TestDbGuard,
}

async fn harness(link_previews: LinkPreviews) -> Harness {
    let (path, guard) = support::TestDbGuard::new("slimm-message-embeds-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    let store = Store::new(pool);
    store
        .create_role(
            "everyone",
            Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES),
            true,
        )
        .await
        .unwrap();
    let app = http::router(AppState {
        store: store.clone(),
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
        media: slimm_server::media::Media::for_tests(),
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
        link_previews,
        dock: slimm_server::http::dock::Dock::disabled(),
        code_runner: slimm_server::code_runner::CodeRunner::disabled(),
    });
    Harness {
        app,
        store,
        _guard: guard,
    }
}

fn request(method: &str, uri: &str, token: Option<&str>) -> Request<Body> {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    builder.body(Body::empty()).unwrap()
}

async fn json_body(response: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

async fn register(store: &Store, username: &str) -> String {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    store
        .open_session(account.id, "cli")
        .await
        .unwrap()
        .access_token
}

async fn messages_in(app: &Router, channel_id: &str, token: &str) -> Vec<Value> {
    let response = app
        .clone()
        .oneshot(request(
            "GET",
            &format!("/channels/{channel_id}/messages"),
            Some(token),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    json_body(response).await.as_array().unwrap().clone()
}

/// The deliverable: an embed the store holds against a message shows up on
/// that message's `embeds` array, in order, with its field and its colour
/// already reduced to a closed accent - never a raw hex - by the time it
/// reaches the wire.
#[tokio::test]
async fn a_stored_embed_is_enriched_onto_its_message() {
    let h = harness(LinkPreviews::disabled()).await;
    let token = register(&h.store, "alice").await;
    let channel = h.store.create_channel("general", "text").await.unwrap();
    let author = h.store.create_user("bot-alice", "bot-alice").await.unwrap();
    let sent = h
        .store
        .send_message(NewMessage::plain(
            channel.id,
            author.id,
            slimm_server::ids::MessageId::generate(),
            "a build result",
        ))
        .await
        .unwrap();

    h.store
        .set_message_embeds(
            sent.message.id,
            &[NewEmbed {
                title: Some("Build failed".to_owned()),
                description: Some("main is red".to_owned()),
                color: Some(0xE0_3B3B),
                fields: vec![NewEmbedField {
                    name: "Job".to_owned(),
                    value: "server-ci".to_owned(),
                    inline: true,
                }],
                ..NewEmbed::default()
            }],
        )
        .await
        .unwrap();

    let messages = messages_in(&h.app, &channel.id.to_string(), &token).await;
    assert_eq!(messages.len(), 1);
    let embeds = messages[0]["embeds"].as_array().unwrap();
    assert_eq!(embeds.len(), 1);
    assert_eq!(embeds[0]["title"], "Build failed");
    assert_eq!(embeds[0]["accent"], "red");
    assert_eq!(embeds[0]["fields"][0]["name"], "Job");
    assert_eq!(embeds[0]["fields"][0]["inline"], true);
    assert!(embeds[0]["image_token"].is_null(), "no image was ever set");
}

/// An ordinary message with no embed carries an empty array, not a missing
/// key or a null - the same "always present" convention `reactions` and
/// `attachments` already follow.
#[tokio::test]
async fn a_message_with_no_embed_has_an_empty_embeds_array() {
    let h = harness(LinkPreviews::disabled()).await;
    let token = register(&h.store, "alice").await;
    let channel = h.store.create_channel("general", "text").await.unwrap();
    h.store
        .send_message(NewMessage::plain(
            channel.id,
            h.store.create_user("alice2", "alice2").await.unwrap().id,
            slimm_server::ids::MessageId::generate(),
            "just text",
        ))
        .await
        .unwrap();

    let messages = messages_in(&h.app, &channel.id.to_string(), &token).await;
    assert_eq!(messages.len(), 1);
    assert_eq!(messages[0]["embeds"], serde_json::json!([]));
}

/// An embed image resolves to a redeemable token, exactly like an ordinary
/// pasted link's preview image - never the raw upstream URL - and only when
/// this deployment has opted into outbound fetching at all.
#[tokio::test]
async fn an_embed_image_resolves_to_a_redeemable_token_when_previews_are_enabled() {
    let h = harness(LinkPreviews::for_test()).await;
    let token = register(&h.store, "alice").await;
    let channel = h.store.create_channel("general", "text").await.unwrap();
    let author = h.store.create_user("bot-alice", "bot-alice").await.unwrap();
    let sent = h
        .store
        .send_message(NewMessage::plain(
            channel.id,
            author.id,
            slimm_server::ids::MessageId::generate(),
            "a snapshot",
        ))
        .await
        .unwrap();
    h.store
        .set_message_embeds(
            sent.message.id,
            &[NewEmbed {
                title: Some("Panel".to_owned()),
                image_url: Some("https://cdn.example.com/panel.png".to_owned()),
                ..NewEmbed::default()
            }],
        )
        .await
        .unwrap();

    let messages = messages_in(&h.app, &channel.id.to_string(), &token).await;
    let token_value = &messages[0]["embeds"][0]["image_token"];
    assert!(
        token_value.is_string(),
        "an enabled deployment must mint a token for a valid image url"
    );
    // Two reads of the same message must not churn the cache into minting a
    // fresh token every time the channel is scrolled past - see
    // `Cache::image_token_for`'s own doc.
    let again = messages_in(&h.app, &channel.id.to_string(), &token).await;
    assert_eq!(again[0]["embeds"][0]["image_token"], *token_value);
}

/// A literal blocked address (the `is_blocked` guard's own cheap, synchronous
/// half) never even reaches the cache: the image is absent from the moment
/// it is enriched, exactly like the disabled-deployment case below.
#[tokio::test]
async fn an_embed_image_pointed_at_a_blocked_address_is_dropped() {
    // `for_test()` sets `allow_private: true` so a test upstream's own
    // loopback is reachable, which would also wave through the very address
    // this test means to prove is refused - so this needs the production
    // guard (`allow_private: false`) with previews merely turned on, built
    // straight from `Config` rather than through `for_test()`.
    let enabled_with_guard = LinkPreviews::new(&Config {
        link_previews: true,
        ..Config::default()
    });
    let h = harness(enabled_with_guard).await;
    let token = register(&h.store, "alice").await;
    let channel = h.store.create_channel("general", "text").await.unwrap();
    let author = h.store.create_user("bot-alice", "bot-alice").await.unwrap();
    let sent = h
        .store
        .send_message(NewMessage::plain(
            channel.id,
            author.id,
            slimm_server::ids::MessageId::generate(),
            "a snapshot",
        ))
        .await
        .unwrap();
    h.store
        .set_message_embeds(
            sent.message.id,
            &[NewEmbed {
                title: Some("Internal panel".to_owned()),
                // A Grafana-style internal-network snapshot - the case
                // decision 0030 names by name: the alert must still arrive.
                image_url: Some("http://169.254.169.254/panel.png".to_owned()),
                ..NewEmbed::default()
            }],
        )
        .await
        .unwrap();

    let messages = messages_in(&h.app, &channel.id.to_string(), &token).await;
    assert!(messages[0]["embeds"][0]["image_token"].is_null());
    assert_eq!(
        messages[0]["embeds"][0]["title"], "Internal panel",
        "the rest of the embed still posts"
    );
}

/// The other half of the same guard: a deployment that has not turned on
/// outbound fetching at all must still post the embed, just with no image -
/// never an error, and never a raw URL leaking to the client instead.
#[tokio::test]
async fn an_embed_image_is_silently_absent_when_link_previews_are_disabled() {
    let h = harness(LinkPreviews::disabled()).await;
    let token = register(&h.store, "alice").await;
    let channel = h.store.create_channel("general", "text").await.unwrap();
    let author = h.store.create_user("bot-alice", "bot-alice").await.unwrap();
    let sent = h
        .store
        .send_message(NewMessage::plain(
            channel.id,
            author.id,
            slimm_server::ids::MessageId::generate(),
            "a snapshot",
        ))
        .await
        .unwrap();
    h.store
        .set_message_embeds(
            sent.message.id,
            &[NewEmbed {
                title: Some("Panel".to_owned()),
                image_url: Some("https://cdn.example.com/panel.png".to_owned()),
                ..NewEmbed::default()
            }],
        )
        .await
        .unwrap();

    let messages = messages_in(&h.app, &channel.id.to_string(), &token).await;
    assert!(messages[0]["embeds"][0]["image_token"].is_null());
    assert_eq!(messages[0]["embeds"][0]["title"], "Panel");
}
