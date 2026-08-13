// SPDX-License-Identifier: AGPL-3.0-only
//! `GET /metrics`: gating, and the shape of the Prometheus text it answers
//! with. See `http/metrics.rs`'s own doc comment for the reasoning.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::json;
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::media::Media;
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use slimm_server::voice::VoiceService;
use tower::ServiceExt;

mod support;

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

fn app(store: Store, voice: VoiceService) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice,
        media: Media::for_tests(),
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
    })
}

fn get(uri: &str, token: &str) -> Request<Body> {
    Request::builder()
        .method("GET")
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap()
}

/// An administrator plus an ordinary member: MANAGE_SERVER on one, nothing
/// beyond @everyone on the other. The same shape `space_analytics.rs` seeds.
async fn deployment(s: &Store) -> (slimm_server::store::User, slimm_server::store::User) {
    s.create_role("everyone", Permissions::VIEW_CHANNEL, true)
        .await
        .unwrap();
    let admin_role = s
        .create_role("admin", Permissions::ADMINISTRATOR, false)
        .await
        .unwrap();
    let admin = s.create_user("root", "Root").await.unwrap();
    s.assign_role(admin.id, admin_role).await.unwrap();
    let member = s.create_user("nia", "Nia").await.unwrap();
    (admin, member)
}

async fn body_text(response: axum::response::Response) -> String {
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    String::from_utf8(bytes.to_vec()).unwrap()
}

#[tokio::test]
async fn an_unauthenticated_caller_is_refused() {
    let (s, _guard) = store("slimm-metrics-unauth").await;
    let router = app(s, VoiceService::disabled());
    let response = router
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/metrics")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
}

/// Gated identically to `/space/analytics`: a caller with only @everyone's
/// bits is refused, same as `space_analytics.rs`'s own
/// `reading_analytics_requires_manage_server`.
#[tokio::test]
async fn a_caller_without_manage_server_is_refused() {
    let (s, _guard) = store("slimm-metrics-forbidden").await;
    let (_admin, member) = deployment(&s).await;
    let session = s.open_session(member.id, "phone").await.unwrap();
    let router = app(s, VoiceService::disabled());
    let response = router
        .oneshot(get("/metrics", &session.access_token))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
}

/// The load-bearing shape test: every non-comment, non-blank line is a valid
/// Prometheus exposition line (`name{labels} value`, or a bare `name value`),
/// every metric that appears has both a `# HELP` and a `# TYPE` line ahead of
/// it, and the four series the mission names are all present. Mutation-tested
/// by hand: dropping any one of the four `write_*` calls in `http/metrics.rs`
/// fails exactly the matching assertion below and nothing else.
#[tokio::test]
async fn a_manage_server_caller_gets_valid_prometheus_text_with_every_series() {
    let (s, _guard) = store("slimm-metrics-shape").await;
    let (admin, _member) = deployment(&s).await;
    let session = s.open_session(admin.id, "laptop").await.unwrap();
    let router = app(s, VoiceService::disabled());
    let response = router
        .oneshot(get("/metrics", &session.access_token))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap()
        .to_owned();
    assert!(content_type.starts_with("text/plain"));

    let text = body_text(response).await;
    assert_prometheus_format(&text);

    assert!(text.contains("slimm_process_resident_memory_bytes "));
    assert!(text.contains("slimm_requests_total{class=\"read\"} "));
    assert!(text.contains("slimm_requests_refused_total{class=\"password\"} "));
    assert!(text.contains("slimm_websocket_connections "));
    // No SFU here: the configured gauge is 0 and the reachable gauge is absent, not a misleading 0.
    assert!(text.contains("slimm_livekit_configured 0"));
    assert!(!text.contains("slimm_livekit_reachable"));
}

/// The one gauge that reflects real traffic within the request itself: the
/// probing call above already spent one `Read`-class request, so this asks
/// again and reads a count of at least 2, rather than trusting a fixed
/// number an unrelated change to route wiring could shift.
#[tokio::test]
async fn the_read_class_counter_reflects_real_requests() {
    let (s, _guard) = store("slimm-metrics-counts").await;
    let (admin, _member) = deployment(&s).await;
    let session = s.open_session(admin.id, "laptop").await.unwrap();
    let router = app(s, VoiceService::disabled());

    let first = router
        .clone()
        .oneshot(get("/metrics", &session.access_token))
        .await
        .unwrap();
    let first_text = body_text(first).await;
    let before = read_count(&first_text);

    let second = router
        .clone()
        .oneshot(get("/metrics", &session.access_token))
        .await
        .unwrap();
    let second_text = body_text(second).await;
    let after = read_count(&second_text);

    assert!(
        after > before,
        "a second /metrics call must itself have counted, {before} then {after}"
    );
}

/// A deployment with an SFU configured, but none reachable at the address
/// given, answers both LiveKit gauges rather than omitting the second one.
#[tokio::test]
async fn a_configured_but_unreachable_sfu_reports_both_gauges() {
    let (s, _guard) = store("slimm-metrics-sfu-down").await;
    let (admin, _member) = deployment(&s).await;
    let session = s.open_session(admin.id, "laptop").await.unwrap();
    // Bound to grab a free port, then dropped so nothing answers on it.
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    drop(listener);
    let voice = VoiceService::for_test(&format!("http://{addr}"), "k", "s");

    let router = app(s, voice);
    let response = router
        .oneshot(get("/metrics", &session.access_token))
        .await
        .unwrap();
    let text = body_text(response).await;
    assert!(text.contains("slimm_livekit_configured 1"));
    assert!(text.contains("slimm_livekit_reachable 0"));
}

fn read_count(text: &str) -> u64 {
    text.lines()
        .find(|line| line.starts_with("slimm_requests_total{class=\"read\"} "))
        .and_then(|line| line.rsplit(' ').next())
        .and_then(|value| value.parse().ok())
        .expect("the read counter line is present and numeric")
}

/// Every metric line the server answers with parses under the Prometheus
/// text exposition grammar: `# HELP <name> <text>`, `# TYPE <name> <kind>`,
/// or `<name>{label="value",...} <number>` / `<name> <number>`. Also checks
/// that every metric name seen on a sample line was introduced by a `# TYPE`
/// line first, since a series with no declared type is not valid exposition
/// text either.
fn assert_prometheus_format(text: &str) {
    assert!(!text.is_empty(), "the body must not be empty");
    assert!(text.ends_with('\n'), "exposition text ends in a newline");

    let mut typed: std::collections::HashSet<&str> = std::collections::HashSet::new();
    for line in text.lines() {
        if let Some(rest) = line.strip_prefix("# TYPE ") {
            let name = rest.split_whitespace().next().unwrap_or_default();
            assert!(
                !name.is_empty(),
                "a `# TYPE` line must name a metric: {line}"
            );
            typed.insert(name);
            continue;
        }
        if line.starts_with("# HELP ") {
            continue;
        }
        assert!(!line.trim().is_empty(), "no blank lines in exposition text");

        let (name_and_labels, value) = line
            .rsplit_once(' ')
            .unwrap_or_else(|| panic!("sample line has no value: {line}"));
        value
            .parse::<f64>()
            .unwrap_or_else(|_| panic!("sample value is not a number: {line}"));

        let name = name_and_labels.split('{').next().unwrap_or_default();
        assert!(
            !name.is_empty()
                && name
                    .chars()
                    .next()
                    .is_some_and(|c| c.is_ascii_alphabetic() || c == '_'),
            "metric name is not a legal Prometheus identifier: {line}"
        );
        assert!(
            typed.contains(name),
            "{name} appears on a sample line with no preceding `# TYPE {name} ...`: {line}"
        );
    }
}

/// Also gated on `Class::Read`'s ordinary rate limit, matching every other
/// authenticated read: a caller who exhausts that budget is refused 429 the
/// same way `/space/analytics` already is.
#[tokio::test]
async fn returns_json_error_shape_on_forbidden_not_a_partial_metrics_body() {
    let (s, _guard) = store("slimm-metrics-forbidden-shape").await;
    let (_admin, member) = deployment(&s).await;
    let session = s.open_session(member.id, "phone").await.unwrap();
    let router = app(s, VoiceService::disabled());
    let response = router
        .oneshot(get("/metrics", &session.access_token))
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::FORBIDDEN);
    let text = body_text(response).await;
    let parsed: serde_json::Value = serde_json::from_str(&text).expect("a JSON error body");
    assert_eq!(parsed, json!({ "error": "insufficient permissions" }));
}
