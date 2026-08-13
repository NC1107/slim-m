// SPDX-License-Identifier: AGPL-3.0-only
//! The running server every case in `script.rs` talks to: one fixture, one
//! request helper, and the record of what has been covered so far.

use std::collections::BTreeSet;
use std::path::Path;

use axum::Router;
use axum::body::Body;
use axum::extract::State;
use axum::http::Request;
use axum::routing::get;
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::gifs::GifSearch;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::media::Media;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use slimm_server::voice::VoiceService;
use tokio::net::TcpListener;
use tower::ServiceExt;

use super::openapi::Api;
use super::verdict::{self, Answer};

pub enum Payload {
    None,
    Json(Value),
    Bytes(Vec<u8>),
}

pub struct Contract {
    state: AppState,
    api: Api,
    covered: BTreeSet<String>,
    problems: Vec<String>,
    /// Held, not read: its drop removes the temp database.
    _db: crate::support::TestDbGuard,
}

impl Contract {
    pub async fn new() -> Contract {
        let (database_path, db_guard) = crate::support::TestDbGuard::new("slimm-response-contract");
        let config = Config {
            port: 0,
            database_path,
            hash_concurrency: 2,
            ..Config::default()
        };
        let pool = db::connect(&config).await.expect("connect + migrate");
        let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
        let repo_root = manifest_dir
            .parent()
            .and_then(Path::parent)
            .expect("crates/slimm-server sits two directories below the repo root");

        let tenor_base = spawn_fake_tenor().await;

        Contract {
            state: AppState {
                store: Store::new(pool),
                auth: Auth::new(2).expect("argon parameters"),
                hub: Hub::new(),
                limiter: RateLimiter::new(),
                push: PushSender::disabled(),
                // Configured rather than disabled so `mintVoiceToken` reaches
                // its documented 200, and its body gets checked, not a 501.
                voice: VoiceService::for_test("wss://sfu.invalid", "devkey", "devsecret"),
                media: Media::for_tests(),
                // Also configured, against a fake local provider, for the same reason.
                gifs: GifSearch::for_test("tenor", &format!("{tenor_base}/v2/search"), "test-key"),
            },
            api: Api::load(repo_root),
            covered: BTreeSet::new(),
            problems: Vec::new(),
            _db: db_guard,
        }
    }

    pub fn operation_ids(&self) -> BTreeSet<String> {
        self.api.operations.keys().cloned().collect()
    }

    pub fn covered(&self) -> &BTreeSet<String> {
        &self.covered
    }

    pub fn problems(&self) -> &[String] {
        &self.problems
    }

    pub async fn get(&mut self, op: &str, uri: &str, token: &str) -> Value {
        self.call(op, "GET", uri, Some(token), Payload::None).await
    }

    pub async fn bare(&mut self, op: &str, method: &str, uri: &str, token: &str) -> Value {
        self.call(op, method, uri, Some(token), Payload::None).await
    }

    pub async fn json(
        &mut self,
        op: &str,
        method: &str,
        uri: &str,
        token: &str,
        body: Value,
    ) -> Value {
        self.call(op, method, uri, Some(token), Payload::Json(body))
            .await
    }

    /// Issues one request and checks the response against the operation the
    /// schema documents under `op`.
    ///
    /// Every request gets a fresh router, and so a fresh rate-limit budget.
    /// A shared one would eventually answer 429 - a status the schema does
    /// document, which is exactly why it would be dangerous here: the
    /// operation would count as visited while its real body was never seen.
    pub async fn call(
        &mut self,
        op: &str,
        method: &str,
        uri: &str,
        token: Option<&str>,
        payload: Payload,
    ) -> Value {
        let mut builder = Request::builder().method(method).uri(uri);
        if let Some(token) = token {
            builder = builder.header("authorization", format!("Bearer {token}"));
        }
        let request = match payload {
            Payload::None => builder.body(Body::empty()),
            Payload::Json(value) => builder
                .header("content-type", "application/json")
                .body(Body::from(value.to_string())),
            Payload::Bytes(bytes) => builder
                .header("content-type", "application/octet-stream")
                .body(Body::from(bytes)),
        }
        .expect("a well-formed request");

        let router = http::router(AppState {
            limiter: RateLimiter::new(),
            ..self.state.clone()
        });
        let response = router.oneshot(request).await.expect("router answered");
        self.covered.insert(op.to_string());

        let status = response.status();
        let media_type = response
            .headers()
            .get("content-type")
            .and_then(|value| value.to_str().ok())
            .map(|value| value.split(';').next().unwrap_or(value).trim().to_owned());
        let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("a readable body");

        let (value, problems) = verdict::judge(
            &self.api,
            Answer {
                op,
                method,
                uri,
                status,
                media_type,
                bytes: &bytes,
            },
        );
        self.problems.extend(problems);
        value
    }
}

/// A search-shaped like a real Tenor `/v2/search` response, embedding
/// `preview.gif`/`full.gif` URLs pointing back at itself, so `searchGifs`,
/// `getGifPreview` and `selectGif` each reach a genuine 2xx here rather than
/// the 501 a disabled `GifSearch` would answer with - the same reason
/// `mintVoiceToken` above is configured rather than disabled.
async fn spawn_fake_tenor() -> String {
    async fn search(State(base): State<String>) -> axum::Json<Value> {
        axum::Json(json!({
            "next": "",
            "results": [{
                "id": "fake-1",
                "content_description": "a cat waving",
                "media_formats": {
                    "tinygif": {"url": format!("{base}/preview.gif"), "dims": [220, 165], "size": 1},
                    "gif": {"url": format!("{base}/full.gif"), "dims": [498, 373], "size": 2}
                }
            }]
        }))
    }
    async fn image() -> Vec<u8> {
        let mut bytes = b"GIF89a".to_vec();
        bytes.extend(std::iter::repeat_n(0u8, 8));
        bytes
    }

    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let base = format!("http://{addr}");
    let router = Router::new()
        .route("/v2/search", get(search))
        .route("/preview.gif", get(image))
        .route("/full.gif", get(image))
        .with_state(base.clone());
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    base
}
