// SPDX-License-Identifier: AGPL-3.0-only
//! slim-m home server.
//!
//! Phase 0 foundation: a minimal but real Axum server that loads configuration,
//! opens the embedded SQLite database, runs migrations, and serves liveness and
//! version endpoints. The messaging protocol, auth, and RBAC arrive in Phase 1.

mod config;
mod db;

use std::net::SocketAddr;

use axum::{Json, Router, extract::State, routing::get};
use serde::Serialize;
use sqlx::SqlitePool;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tower_http::trace::TraceLayer;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // `--healthcheck` is how the distroless container image checks liveness,
    // since that image has no shell for a curl-based Docker HEALTHCHECK.
    if std::env::args().nth(1).as_deref() == Some("--healthcheck") {
        return healthcheck().await;
    }

    init_tracing();
    let config = config::Config::from_env()?;
    let pool = db::connect(&config).await?;

    let app = router(pool);
    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    let listener = TcpListener::bind(addr).await?;
    tracing::info!(%addr, version = env!("CARGO_PKG_VERSION"), "slim-m server listening");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;

    Ok(())
}

fn router(pool: SqlitePool) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/version", get(version))
        .layer(TraceLayer::new_for_http())
        .with_state(pool)
}

/// Liveness probe. Returns 200 as long as the process is serving requests.
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

/// Reports the build version and the wire-protocol envelope version a client
/// negotiates against.
async fn version() -> Json<Version> {
    Json(Version {
        name: "slim-m",
        version: env!("CARGO_PKG_VERSION"),
        protocol: 1,
    })
}

/// Minimal error type so a failed liveness check returns 503 rather than panics.
struct StatusError;

impl axum::response::IntoResponse for StatusError {
    fn into_response(self) -> axum::response::Response {
        (axum::http::StatusCode::SERVICE_UNAVAILABLE, "unavailable").into_response()
    }
}

/// Connects to the local server and confirms `/healthz` returns 200.
async fn healthcheck() -> anyhow::Result<()> {
    let port: u16 = std::env::var("SLIMM_PORT")
        .ok()
        .and_then(|value| value.parse().ok())
        .unwrap_or(8080);

    let mut stream = TcpStream::connect(("127.0.0.1", port)).await?;
    stream
        .write_all(b"GET /healthz HTTP/1.0\r\nHost: localhost\r\n\r\n")
        .await?;

    let mut response = Vec::new();
    stream.read_to_end(&mut response).await?;
    let response = String::from_utf8_lossy(&response);

    if response.starts_with("HTTP/1.0 200") || response.starts_with("HTTP/1.1 200") {
        Ok(())
    } else {
        anyhow::bail!("health check failed: unexpected response")
    }
}

fn init_tracing() {
    use tracing_subscriber::EnvFilter;
    let filter = EnvFilter::try_from_env("SLIMM_LOG").unwrap_or_else(|_| EnvFilter::new("info"));
    tracing_subscriber::fmt().with_env_filter(filter).init();
}

/// Resolves on Ctrl-C or SIGTERM so the container stops cleanly.
async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c()
            .await
            .expect("install Ctrl-C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("install SIGTERM handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }

    tracing::info!("shutdown signal received, stopping");
}
