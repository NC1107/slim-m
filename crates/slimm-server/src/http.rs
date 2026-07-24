// SPDX-License-Identifier: AGPL-3.0-only
//! HTTP surface: liveness, version, and the auth routes. The messaging and
//! WebSocket routes are added as the protocol is built.

use axum::{Json, Router, extract::State, routing::get};
use serde::Serialize;
use tower_http::trace::TraceLayer;

use crate::auth::Auth;
use crate::store::Store;

mod auth;

/// What every handler shares: the persistence layer and the auth service.
/// Cloning is cheap (a pool handle and a couple of `Arc`s).
#[derive(Clone)]
pub struct AppState {
    pub store: Store,
    pub auth: Auth,
}

/// Builds the router over the shared application state.
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/version", get(version))
        .merge(auth::routes())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

/// Liveness probe: 200 while the process is serving and the database answers.
async fn healthz(State(state): State<AppState>) -> Result<&'static str, StatusError> {
    state.store.ping().await.map_err(|_| StatusError)?;
    Ok("ok")
}

#[derive(Serialize)]
struct Version {
    name: &'static str,
    version: &'static str,
    protocol: u32,
}

/// Build version and the wire-protocol envelope version a client negotiates.
async fn version() -> Json<Version> {
    Json(Version {
        name: "slim-m",
        version: env!("CARGO_PKG_VERSION"),
        protocol: 1,
    })
}

/// Minimal error so a failed liveness check returns 503 rather than panicking.
struct StatusError;

impl axum::response::IntoResponse for StatusError {
    fn into_response(self) -> axum::response::Response {
        (axum::http::StatusCode::SERVICE_UNAVAILABLE, "unavailable").into_response()
    }
}
