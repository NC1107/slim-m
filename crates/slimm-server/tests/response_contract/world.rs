// SPDX-License-Identifier: AGPL-3.0-only
//! The running server every case in `script.rs` talks to: one fixture, one
//! request helper, and the record of what has been covered so far.

use std::collections::BTreeSet;
use std::path::Path;

use axum::body::Body;
use axum::http::Request;
use serde_json::Value;
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::media::Media;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use slimm_server::voice::VoiceService;
use tower::ServiceExt;
use uuid::Uuid;

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
}

impl Contract {
    pub async fn new() -> Contract {
        let database_path = std::env::temp_dir()
            .join(format!("slimm-response-contract-{}.db", Uuid::now_v7()))
            .to_string_lossy()
            .into_owned();
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
            },
            api: Api::load(repo_root),
            covered: BTreeSet::new(),
            problems: Vec::new(),
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
