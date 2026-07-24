// SPDX-License-Identifier: AGPL-3.0-only
//! slim-m home server.
//!
//! The binary in `main.rs` is a thin wrapper; the server logic lives here as a
//! library so it can be exercised by integration tests.

pub mod auth;
pub mod config;
pub mod db;
pub mod http;
pub mod ids;
pub mod store;

use std::net::SocketAddr;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

/// Loads configuration, opens the embedded database (running migrations), and
/// serves the HTTP surface until a shutdown signal.
pub async fn run() -> anyhow::Result<()> {
    init_tracing();
    let config = config::Config::from_env()?;
    let pool = db::connect(&config).await?;

    let store = store::Store::new(pool);
    let auth = auth::Auth::new(config.hash_concurrency)?;
    let app = http::router(http::AppState { store, auth });
    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    let listener = TcpListener::bind(addr).await?;
    tracing::info!(%addr, version = env!("CARGO_PKG_VERSION"), "slim-m server listening");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

/// Connects to the local server and confirms `/healthz` returns 200. Used by the
/// container image's healthcheck, since distroless has no shell.
pub async fn healthcheck() -> anyhow::Result<()> {
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
