// SPDX-License-Identifier: AGPL-3.0-only
//! slim-m home server.
//!
//! The binary in `main.rs` is a thin wrapper; the server logic lives here as a
//! library so it can be exercised by integration tests.

pub mod auth;
pub mod config;
pub mod cors;
pub mod db;
pub mod http;
pub mod hub;
pub mod identity;
pub mod ids;
pub mod media;
pub mod permissions;
pub mod presence;
pub mod push;
pub mod ratelimit;
pub mod store;
pub mod typing;
pub mod voice;

use std::net::SocketAddr;

use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

/// Loads configuration, opens the embedded database (running migrations), and
/// serves the HTTP surface until a shutdown signal.
pub async fn run() -> anyhow::Result<()> {
    init_tracing();
    let config = config::Config::from_env()?;
    // Before the database is touched, so a misconfigured origin list is a
    // startup error and not a half-initialized deployment.
    let cors = cors::CorsPolicy::new(&config)?;
    let pool = db::connect(&config).await?;

    let store = store::Store::new(pool);
    spawn_token_sweep(store.clone());
    let media = media::Media::new(config.attachments_dir.clone(), config.attachment_max_bytes)?;
    spawn_attachment_sweep(store.clone(), media.clone());
    let auth = auth::Auth::new(config.hash_concurrency)?;
    let hub = hub::Hub::new();
    let limiter = ratelimit::RateLimiter::new();
    let push = push::PushSender::new(&config)?;
    let voice = voice::VoiceService::new(&config)?;
    let app = cors.apply(http::router(http::AppState {
        store,
        auth,
        hub,
        limiter,
        push,
        voice,
        media,
    }));
    let addr = SocketAddr::from(([0, 0, 0, 0], config.port));
    let listener = TcpListener::bind(addr).await?;
    tracing::info!(%addr, version = env!("CARGO_PKG_VERSION"), "slim-m server listening");

    axum::serve(
        listener,
        app.into_make_service_with_connect_info::<SocketAddr>(),
    )
    .with_graceful_shutdown(shutdown_signal())
    .await?;
    Ok(())
}

/// How often expired token rows are swept. Long, because nothing depends on
/// the rows going promptly: they are already refused by their own `expires_at`
/// checks, and this only reclaims the space and keeps the indexes over them
/// from growing without bound for the life of a deployment.
const TOKEN_SWEEP_INTERVAL: std::time::Duration = std::time::Duration::from_secs(6 * 60 * 60);

/// Runs the token sweep in the background for the life of the process.
///
/// Detached and best-effort: a failed sweep is logged and retried on the next
/// tick, never propagated, because nothing a request does depends on it. The
/// first tick waits out the interval rather than running at startup, so a
/// container that crash-loops does not hammer the same delete on every boot.
fn spawn_token_sweep(store: store::Store) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(TOKEN_SWEEP_INTERVAL);
        ticker.tick().await;
        loop {
            ticker.tick().await;
            match store.sweep_expired_tokens().await {
                Ok(swept) if swept.total() > 0 => {
                    tracing::info!(
                        access_tokens = swept.access_tokens,
                        refresh_tokens = swept.refresh_tokens,
                        ws_tickets = swept.ws_tickets,
                        "swept expired token rows"
                    );
                }
                Ok(_) => {}
                Err(err) => tracing::warn!(error = %err, "token sweep failed"),
            }
        }
    });
}

/// How often an uploaded-but-never-attached attachment is swept. Uploading is
/// two-phase (bytes first, a message reference second), so an interrupted
/// compose leaves a real, if bounded, class of orphan this reclaims; see
/// `store::attachments` for the grace window and per-pass batch size.
const ATTACHMENT_SWEEP_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60 * 60);

/// Runs the orphaned-attachment sweep in the background for the life of the
/// process, on the same detached, best-effort, wait-first model as
/// [`spawn_token_sweep`]. The database rows are removed first (inside the
/// store call); this only cleans up the backing files that removal freed,
/// which is why it needs `media` and not just `store`.
fn spawn_attachment_sweep(store: store::Store, media: media::Media) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(ATTACHMENT_SWEEP_INTERVAL);
        ticker.tick().await;
        loop {
            ticker.tick().await;
            match store.sweep_orphaned_attachments().await {
                Ok(freed) if !freed.is_empty() => {
                    tracing::info!(count = freed.len(), "swept orphaned attachment rows");
                    for hex in freed {
                        if let Err(err) = media.delete_attachment(&hex).await {
                            tracing::warn!(error = %err, attachment = %hex, "failed to delete a swept attachment file");
                        }
                    }
                }
                Ok(_) => {}
                Err(err) => tracing::warn!(error = %err, "attachment sweep failed"),
            }
        }
    });
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
