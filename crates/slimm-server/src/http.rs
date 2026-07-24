// SPDX-License-Identifier: AGPL-3.0-only
//! HTTP surface. Phase 0 liveness and version endpoints; the messaging and auth
//! routes are added as the protocol is built.

use axum::{Json, Router, extract::State, routing::get};
use serde::Serialize;
use sqlx::SqlitePool;
use tower_http::trace::TraceLayer;

/// Builds the router with the database pool as shared state.
pub fn router(pool: SqlitePool) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/version", get(version))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

/// Liveness probe: 200 while the process is serving and the database answers.
async fn healthz(State(pool): State<SqlitePool>) -> Result<&'static str, StatusError> {
    sqlx::query("SELECT 1")
        .execute(&pool)
        .await
        .map_err(|_| StatusError)?;
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
