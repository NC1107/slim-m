// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The Dock's HTTP surface: MANAGE_SERVER gating on every route, the
//! install/enable/disable/uninstall lifecycle against a fake local registry,
//! a version mismatch on install, and an oversized response being refused.
//! See docs/decisions/0021-modules-and-the-dock.md.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use axum::routing::get;
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::dock::Dock;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::media::Media;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::{Store, User};
use slimm_server::voice::VoiceService;
use tokio::net::TcpListener;
use tower::ServiceExt;

mod support;

const GOOD_MANIFEST: &str = r#"{
    "schema": 1,
    "id": "code-exec",
    "name": "Code Blocks",
    "version": "0.1.0",
    "summary": "runs code",
    "artifact": {
        "kind": "wasm",
        "path": "modules/code-exec/0.1.0/module.wasm",
        "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
    },
    "runtime": {"backend": "wasm", "limits": {"memory_mb": 64, "wall_ms": 2000, "fuel": 500000000}},
    "permissions": [
        {"key": "run", "name": "Execute code blocks", "description": "run a snippet"}
    ],
    "capabilities": ["command.register", "message.post"],
    "extension_points": [
        {"kind": "command", "name": "run", "description": "runs it"}
    ]
}"#;

const GOOD_INDEX: &str = r#"{
    "schema": 1,
    "modules": [
        {"id": "code-exec", "name": "Code Blocks", "version": "0.1.0", "summary": "runs code"}
    ]
}"#;

async fn store(name: &str) -> (Store, support::TestDbGuard) {
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

fn app(store: Store, dock: Dock) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: VoiceService::disabled(),
        media: Media::for_tests(),
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
        link_previews: slimm_server::http::link_preview::LinkPreviews::disabled(),
        dock,
    })
}

async fn deployment(s: &Store) -> (User, User) {
    let view_send = Permissions::VIEW_CHANNEL.union(Permissions::SEND_MESSAGES);
    s.create_role("everyone", view_send, true).await.unwrap();
    let admin_role = s
        .create_role("admin", Permissions::ADMINISTRATOR, false)
        .await
        .unwrap();
    let admin = s.create_user("root", "Root").await.unwrap();
    s.assign_role(admin.id, admin_role).await.unwrap();
    let member = s.create_user("nia", "Nia").await.unwrap();
    (admin, member)
}

fn req(method: &str, uri: &str, token: &str) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap()
}

fn req_json(method: &str, uri: &str, token: &str, body: Value) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .body(Body::from(body.to_string()))
        .unwrap()
}

async fn json_body(response: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap()
}

/// Serves a fixed `index.json` and `manifest.json` for `code-exec`, the same
/// fixture the response-contract pass and `http::dock::manifest`'s own tests
/// use.
async fn fake_registry() -> String {
    async fn index() -> axum::Json<Value> {
        axum::Json(serde_json::from_str(GOOD_INDEX).unwrap())
    }
    async fn manifest() -> axum::Json<Value> {
        axum::Json(serde_json::from_str(GOOD_MANIFEST).unwrap())
    }
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let base = format!("http://{addr}/");
    let router = Router::new()
        .route("/index.json", get(index))
        .route("/modules/code-exec/manifest.json", get(manifest));
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    base
}

/// Serves an `index.json` well over `MAX_INDEX_BYTES`, to prove a fetch cap
/// applies rather than buffering an unbounded body.
async fn fake_oversized_registry() -> String {
    async fn index() -> String {
        let padding = "x".repeat(400 * 1024);
        format!(r#"{{"schema": 1, "modules": [], "padding": "{padding}"}}"#)
    }
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let base = format!("http://{addr}/");
    let router = Router::new().route("/index.json", get(index));
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    base
}

#[tokio::test]
async fn manage_server_is_required_for_every_dock_route() {
    let (s, _guard) = store("slimm-dock-forbidden").await;
    let (_admin, member) = deployment(&s).await;
    let session = s.open_session(member.id, "phone").await.unwrap();
    let token = session.access_token.as_str();
    let dock = Dock::for_test(&fake_registry().await);
    let router = app(s, dock);

    let routes: &[(&str, &str)] = &[
        ("GET", "/space/dock/modules"),
        ("GET", "/space/dock/modules/code-exec"),
        ("POST", "/space/dock/modules/code-exec/enable"),
        ("POST", "/space/dock/modules/code-exec/disable"),
        ("DELETE", "/space/dock/modules/code-exec/install"),
        ("GET", "/space/dock/installed"),
    ];
    for (method, uri) in routes {
        let response = router
            .clone()
            .oneshot(req(method, uri, token))
            .await
            .unwrap();
        assert_eq!(
            response.status(),
            StatusCode::FORBIDDEN,
            "{method} {uri} should require MANAGE_SERVER"
        );
    }

    let install_response = router
        .clone()
        .oneshot(req_json(
            "POST",
            "/space/dock/modules/code-exec/install",
            token,
            json!({ "version": "0.1.0" }),
        ))
        .await
        .unwrap();
    assert_eq!(install_response.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn install_registers_permissions_and_uninstall_removes_them() {
    let (s, _guard) = store("slimm-dock-install-lifecycle").await;
    let (admin, _member) = deployment(&s).await;
    let session = s.open_session(admin.id, "laptop").await.unwrap();
    let token = session.access_token.as_str();
    let dock = Dock::for_test(&fake_registry().await);
    let router = app(s.clone(), dock);

    let install_response = router
        .clone()
        .oneshot(req_json(
            "POST",
            "/space/dock/modules/code-exec/install",
            token,
            json!({ "version": "0.1.0" }),
        ))
        .await
        .unwrap();
    assert_eq!(install_response.status(), StatusCode::OK);
    let installed = json_body(install_response).await;
    assert_eq!(installed["id"], json!("code-exec"));
    assert_eq!(installed["enabled"], json!(false));

    let perms = s.list_module_permissions().await.unwrap();
    assert_eq!(perms.len(), 1);
    assert_eq!(perms[0].module_id, "code-exec");
    assert_eq!(perms[0].perm_key, "run");

    let enable_response = router
        .clone()
        .oneshot(req("POST", "/space/dock/modules/code-exec/enable", token))
        .await
        .unwrap();
    assert_eq!(enable_response.status(), StatusCode::OK);
    assert_eq!(json_body(enable_response).await["enabled"], json!(true));

    let uninstall_response = router
        .clone()
        .oneshot(req(
            "DELETE",
            "/space/dock/modules/code-exec/install",
            token,
        ))
        .await
        .unwrap();
    assert_eq!(uninstall_response.status(), StatusCode::NO_CONTENT);

    assert!(s.installed_module("code-exec").await.unwrap().is_none());
    assert!(s.list_module_permissions().await.unwrap().is_empty());

    // Idempotent-in-shape: a second uninstall 404s rather than succeeding twice.
    let second_uninstall = router
        .oneshot(req(
            "DELETE",
            "/space/dock/modules/code-exec/install",
            token,
        ))
        .await
        .unwrap();
    assert_eq!(second_uninstall.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn install_refuses_a_version_that_no_longer_matches_the_registry() {
    let (s, _guard) = store("slimm-dock-version-mismatch").await;
    let (admin, _member) = deployment(&s).await;
    let session = s.open_session(admin.id, "laptop").await.unwrap();
    let token = session.access_token.as_str();
    let dock = Dock::for_test(&fake_registry().await);
    let router = app(s, dock);

    let response = router
        .oneshot(req_json(
            "POST",
            "/space/dock/modules/code-exec/install",
            token,
            json!({ "version": "9.9.9" }),
        ))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::CONFLICT);
}

#[tokio::test]
async fn an_oversized_registry_response_is_refused_rather_than_buffered() {
    let (s, _guard) = store("slimm-dock-oversized").await;
    let (admin, _member) = deployment(&s).await;
    let session = s.open_session(admin.id, "laptop").await.unwrap();
    let token = session.access_token.as_str();
    let dock = Dock::for_test(&fake_oversized_registry().await);
    let router = app(s, dock);

    let response = router
        .oneshot(req("GET", "/space/dock/modules", token))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
}
