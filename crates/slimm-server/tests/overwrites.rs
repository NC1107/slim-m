// SPDX-License-Identifier: AGPL-3.0-only
//! Channel permission overwrites: MANAGE_ROLES is checked in the channel
//! itself (not the deployment-wide base), a nonexistent channel is refused
//! identically to a real one the caller cannot manage, `allow` cannot grant a
//! bit the caller lacks, and a set overwrite actually changes what the
//! evaluator returns.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use tower::ServiceExt;
use uuid::Uuid;

async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-overwrites-test-{}.db", Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        push_relay_url: None,
        push_relay_key: None,
        livekit_url: None,
        livekit_api_key: None,
        livekit_api_secret: None,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

fn app(store: Store) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
    })
}

fn request(method: &str, uri: &str, token: Option<&str>, body: Option<Value>) -> Request<Body> {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
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
    serde_json::from_slice(&bytes).unwrap()
}

/// A member with a session, built straight through the store.
///
/// Deliberately not the `/auth/register` route: joining a claimed deployment
/// is an invite-gated policy decision, and it is pinned by its own tests in
/// `registration_gate.rs`. These tests only need somebody signed in, so going
/// through the store keeps them independent of that policy.
async fn register(store: &Store, username: &str) -> (String, String) {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    // The first account through here claims the deployment, exactly as the
    // first real registration does; later ones find it already set up.
    store.bootstrap_deployment(account.id).await.unwrap();
    let tokens = store.open_session(account.id, "cli").await.unwrap();
    (tokens.access_token, account.id.to_string())
}

async fn general_channel_id(store: &Store) -> String {
    store
        .list_channels()
        .await
        .unwrap()
        .into_iter()
        .next()
        .expect("bootstrap seeds a general channel")
        .id
        .to_string()
}

async fn everyone_role_id(store: &Store) -> String {
    store
        .list_roles()
        .await
        .unwrap()
        .into_iter()
        .find(|r| r.is_everyone)
        .expect("bootstrap seeds @everyone")
        .id
        .to_string()
}

async fn send_message(app: &Router, channel_id: &str, token: &str) -> StatusCode {
    app.clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{channel_id}/messages"),
            Some(token),
            Some(json!({ "id": Uuid::now_v7().to_string(), "content": "hi" })),
        ))
        .await
        .unwrap()
        .status()
}

// ---------------------------------------------------------------------------
// Existence hiding
// ---------------------------------------------------------------------------

/// A channel that does not exist grants MANAGE_ROLES to nobody, administrator
/// included, since `permissions_in_channel` returns nothing at all before an
/// administrator bypass is even considered. The point is that a bogus channel
/// id and a real channel the caller cannot manage must answer identically.
#[tokio::test]
async fn nonexistent_channel_refuses_identically_for_everyone() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let everyone = everyone_role_id(&store).await;

    let missing_channel = Uuid::now_v7().to_string();
    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/channels/{missing_channel}/overwrites/role/{everyone}"),
            Some(&admin_token),
            Some(json!({ "allow": 0, "deny": 0 })),
        ))
        .await
        .unwrap();
    assert_eq!(
        response.status(),
        StatusCode::FORBIDDEN,
        "a nonexistent channel must not be distinguishable from one the caller cannot manage"
    );
}

// ---------------------------------------------------------------------------
// Escalation
// ---------------------------------------------------------------------------

/// A MANAGE_ROLES holder in a channel cannot force-allow a permission they do
/// not themselves hold there, even for themselves.
#[tokio::test]
async fn allow_cannot_grant_a_permission_the_caller_lacks() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (member_token, member_id) = register(&store, "bob").await;
    let channel_id = general_channel_id(&store).await;

    // Bob holds MANAGE_ROLES (via a role) but never BAN_MEMBERS.
    let manager_role = store
        .create_role("manager", Permissions::MANAGE_ROLES, false)
        .await
        .unwrap();
    store
        .assign_role(
            slimm_server::ids::UserId(Uuid::parse_str(&member_id).unwrap()),
            manager_role,
        )
        .await
        .unwrap();

    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/channels/{channel_id}/overwrites/member/{member_id}"),
            Some(&member_token),
            Some(json!({ "allow": Permissions::BAN_MEMBERS.bits(), "deny": 0 })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);

    // The same admin-only token can, since ADMINISTRATOR resolves to ALL.
    let allowed = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/channels/{channel_id}/overwrites/member/{member_id}"),
            Some(&admin_token),
            Some(json!({ "allow": Permissions::BAN_MEMBERS.bits(), "deny": 0 })),
        ))
        .await
        .unwrap();
    assert_eq!(allowed.status(), StatusCode::NO_CONTENT);
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

#[tokio::test]
async fn kind_must_be_role_or_member() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let channel_id = general_channel_id(&store).await;

    let response = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/channels/{channel_id}/overwrites/bogus/{}", Uuid::now_v7()),
            Some(&admin_token),
            Some(json!({ "allow": 0, "deny": 0 })),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn setting_an_overwrite_for_a_nonexistent_target_is_not_found() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let channel_id = general_channel_id(&store).await;

    let no_such_role = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/channels/{channel_id}/overwrites/role/{}", Uuid::now_v7()),
            Some(&admin_token),
            Some(json!({ "allow": 0, "deny": 0 })),
        ))
        .await
        .unwrap();
    assert_eq!(no_such_role.status(), StatusCode::NOT_FOUND);

    let no_such_member = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!(
                "/channels/{channel_id}/overwrites/member/{}",
                Uuid::now_v7()
            ),
            Some(&admin_token),
            Some(json!({ "allow": 0, "deny": 0 })),
        ))
        .await
        .unwrap();
    assert_eq!(no_such_member.status(), StatusCode::NOT_FOUND);
}

// ---------------------------------------------------------------------------
// The evaluator actually honours what gets set
// ---------------------------------------------------------------------------

/// Denying SEND_MESSAGES for `@everyone` in a channel takes effect at once,
/// a member overwrite re-grants it to one person despite that, and clearing
/// the `@everyone` overwrite restores the default for everyone else.
#[tokio::test]
async fn set_and_clear_actually_change_what_the_evaluator_returns() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let (carol_token, carol_id) = register(&store, "carol").await;
    let channel_id = general_channel_id(&store).await;
    let everyone = everyone_role_id(&store).await;

    assert_eq!(
        send_message(&app, &channel_id, &carol_token).await,
        StatusCode::OK,
        "SEND_MESSAGES is in the @everyone default"
    );

    let deny = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/channels/{channel_id}/overwrites/role/{everyone}"),
            Some(&admin_token),
            Some(json!({ "allow": 0, "deny": Permissions::SEND_MESSAGES.bits() })),
        ))
        .await
        .unwrap();
    assert_eq!(deny.status(), StatusCode::NO_CONTENT);
    assert_eq!(
        send_message(&app, &channel_id, &carol_token).await,
        StatusCode::FORBIDDEN,
        "the @everyone deny must take effect immediately"
    );

    let regrant = app
        .clone()
        .oneshot(request(
            "PUT",
            &format!("/channels/{channel_id}/overwrites/member/{carol_id}"),
            Some(&admin_token),
            Some(json!({ "allow": Permissions::SEND_MESSAGES.bits(), "deny": 0 })),
        ))
        .await
        .unwrap();
    assert_eq!(regrant.status(), StatusCode::NO_CONTENT);
    assert_eq!(
        send_message(&app, &channel_id, &carol_token).await,
        StatusCode::OK,
        "a member overwrite is absolute and re-grants over the role-tier deny"
    );

    let clear = app
        .clone()
        .oneshot(request(
            "DELETE",
            &format!("/channels/{channel_id}/overwrites/role/{everyone}"),
            Some(&admin_token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(clear.status(), StatusCode::NO_CONTENT);

    let (dave_token, _dave_id) = register(&store, "dave").await;
    assert_eq!(
        send_message(&app, &channel_id, &dave_token).await,
        StatusCode::OK,
        "clearing the @everyone deny restores the default for a member who never had an override"
    );
}

/// Clearing an overwrite that was never set is not an error.
#[tokio::test]
async fn clearing_an_unset_overwrite_is_idempotent() {
    let store = new_store().await;
    let app = app(store.clone());
    let (admin_token, _admin_id) = register(&store, "alice").await;
    let channel_id = general_channel_id(&store).await;
    let everyone = everyone_role_id(&store).await;

    let response = app
        .clone()
        .oneshot(request(
            "DELETE",
            &format!("/channels/{channel_id}/overwrites/role/{everyone}"),
            Some(&admin_token),
            None,
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::NO_CONTENT);
}

/// Clearing a deny grants that permission just as surely as setting an allow.
/// Judging a write by its `allow` bits alone let a caller strip a deny and hand
/// themselves a bit they could never have granted directly.
#[tokio::test]
async fn clearing_a_deny_you_do_not_hold_is_refused() {
    let store = new_store().await;
    let app = app(store.clone());

    // First account claims the deployment and is its administrator.
    let (admin, _admin_id) = register(&store, "admin").await;
    let (moderator, moderator_id) = register(&store, "moderator").await;
    let channel = general_channel_id(&store).await;

    // The moderator may manage roles, but never gets MANAGE_SERVER.
    let role = json_body(
        app.clone()
            .oneshot(request(
                "POST",
                "/roles",
                Some(&admin),
                Some(json!({
                    "name": "moderator",
                    "permissions": Permissions::VIEW_CHANNEL
                        .union(Permissions::MANAGE_ROLES)
                        .bits()
                })),
            ))
            .await
            .unwrap(),
    )
    .await;
    let role_id = role["id"].as_str().unwrap().to_owned();
    app.clone()
        .oneshot(request(
            "PUT",
            &format!("/members/{moderator_id}/roles/{role_id}"),
            Some(&admin),
            None,
        ))
        .await
        .unwrap();

    // The administrator denies MANAGE_SERVER to that role in this channel.
    let overwrite = format!("/channels/{channel}/overwrites/role/{role_id}");
    let denied = app
        .clone()
        .oneshot(request(
            "PUT",
            &overwrite,
            Some(&admin),
            Some(json!({ "allow": 0, "deny": Permissions::MANAGE_SERVER.bits() })),
        ))
        .await
        .unwrap();
    assert_eq!(denied.status(), StatusCode::NO_CONTENT);

    // Rewriting the overwrite to drop the deny would grant MANAGE_SERVER, which
    // the moderator does not hold.
    let rewrite = app
        .clone()
        .oneshot(request(
            "PUT",
            &overwrite,
            Some(&moderator),
            Some(json!({ "allow": 0, "deny": 0 })),
        ))
        .await
        .unwrap();
    assert_eq!(
        rewrite.status(),
        StatusCode::FORBIDDEN,
        "dropping a deny grants that bit, so it needs the same check setting an allow does"
    );

    // And deleting the overwrite outright must not be the way around it.
    let cleared = app
        .clone()
        .oneshot(request("DELETE", &overwrite, Some(&moderator), None))
        .await
        .unwrap();
    assert_eq!(
        cleared.status(),
        StatusCode::FORBIDDEN,
        "clearing an overwrite grants back everything it denied"
    );
}
