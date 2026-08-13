// SPDX-License-Identifier: AGPL-3.0-only
//! slim-m home server.
//!
//! The binary in `main.rs` is a thin wrapper; the server logic lives here as a
//! library so it can be exercised by integration tests.

pub mod auth;
pub mod config;
pub mod cors;
pub mod db;
pub mod emoji;
pub mod http;
pub mod hub;
pub mod identity;
pub mod ids;
pub mod media;
pub mod notifications;
pub mod permissions;
pub mod presence;
mod process_metrics;
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
    let media = media::Media::new(config.attachments_dir.clone(), config.attachment_max_bytes)?
        .with_total_ceiling(config.max_total_attachment_bytes);
    spawn_attachment_sweep(store.clone(), media.clone());
    spawn_canvas_op_sweep(store.clone());
    let auth = auth::Auth::new(config.hash_concurrency)?;
    let hub = hub::Hub::new();
    let limiter = ratelimit::RateLimiter::with_trusted_hops(config.trust_proxy_hops);
    let push = push::PushSender::new(&config)?;
    let voice = voice::VoiceService::new(&config)?;
    spawn_call_sweep(voice.clone(), hub.clone());
    spawn_message_retention_sweep(store.clone(), media.clone(), hub.clone());
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

/// How often the canvas op log is compacted. Long, the same reasoning
/// [`TOKEN_SWEEP_INTERVAL`] gives: nothing depends on a `remove`, `clear` or
/// `restore` row going away promptly, this only bounds how far the log grows
/// for the life of a deployment. A read-triggered sweep (the analytics
/// sampling model) was considered and rejected: this is a real `DELETE` with
/// a cost proportional to what it reclaims, not a cheap read, and a channel
/// drawn in continuously but never read through whatever request would
/// trigger it would never be swept at all - the opposite of what bounding
/// growth needs.
const CANVAS_OP_SWEEP_INTERVAL: std::time::Duration = std::time::Duration::from_secs(6 * 60 * 60);

/// Runs the canvas op compaction sweep in the background for the life of the
/// process, on the same detached, best-effort, wait-first model as
/// [`spawn_token_sweep`].
fn spawn_canvas_op_sweep(store: store::Store) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(CANVAS_OP_SWEEP_INTERVAL);
        ticker.tick().await;
        loop {
            ticker.tick().await;
            match store.sweep_canvas_ops().await {
                Ok(swept) if swept.total() > 0 => {
                    tracing::info!(
                        restores = swept.restores,
                        removes = swept.removes,
                        clears = swept.clears,
                        "compacted canvas op rows"
                    );
                }
                Ok(_) => {}
                Err(err) => tracing::warn!(error = %err, "canvas op sweep failed"),
            }
        }
    });
}

/// How often a stale voice heartbeat is checked for. Short, unlike the token
/// and attachment sweeps: this bounds how long a terminated app's ghost
/// participant lingers, so the interval is part of that bound rather than
/// housekeeping on its own schedule; see `voice::heartbeat`.
const CALL_SWEEP_INTERVAL: std::time::Duration = std::time::Duration::from_secs(10);

/// Runs the stale-voice-call sweep in the background for the life of the
/// process, on the same detached, best-effort, wait-first model as
/// [`spawn_token_sweep`]. A deployment with no SFU configured never has
/// anything to sweep, so this is safe to spawn unconditionally.
fn spawn_call_sweep(voice: voice::VoiceService, hub: hub::Hub) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(CALL_SWEEP_INTERVAL);
        ticker.tick().await;
        loop {
            ticker.tick().await;
            sweep_stale_voice_calls(&voice, &hub).await;
        }
    });
}

/// One pass of the stale-call sweep, evicting every call whose heartbeat has
/// gone stale as of now.
pub async fn sweep_stale_voice_calls(voice: &voice::VoiceService, hub: &hub::Hub) {
    sweep_stale_voice_calls_at(voice, hub, std::time::Instant::now()).await;
}

/// [`sweep_stale_voice_calls`] with an explicit clock.
///
/// Split out of [`spawn_call_sweep`]'s loop, and `pub` rather than private,
/// so a test can drive the real coupling between
/// [`voice::VoiceService::sweep_stale_calls_at`] and
/// [`voice::VoiceService::remove_participant`] against a controlled clock,
/// rather than re-implementing the loop and risking the copy drifting from
/// what actually runs.
///
/// Publishes [`hub::Event::VoiceActivityChanged`] for every evicted
/// `(user, channel)` pair regardless of whether the best-effort SFU removal
/// below it succeeds: the heartbeat going stale is already the real
/// transition, committed by [`voice::VoiceService::sweep_stale_calls_at`]
/// before this loop ever runs.
pub async fn sweep_stale_voice_calls_at(
    voice: &voice::VoiceService,
    hub: &hub::Hub,
    now: std::time::Instant,
) {
    for (user_id, channel_id) in voice.sweep_stale_calls_at(now) {
        hub.publish(hub::Event::VoiceActivityChanged { channel_id });
        match voice.remove_participant(channel_id, user_id).await {
            Ok(()) => tracing::info!(
                %user_id,
                %channel_id,
                "removed a voice participant with no recent heartbeat"
            ),
            Err(voice::VoiceError::Unavailable) => {}
            Err(voice::VoiceError::Internal(err)) => tracing::warn!(
                error = %err,
                %user_id,
                %channel_id,
                "failed to remove a stale voice participant"
            ),
        }
    }
}

/// How often the message retention window is applied. Long, the same
/// reasoning [`TOKEN_SWEEP_INTERVAL`] gives: a day-granularity setting has
/// no reason to be checked more often than this, and a deployment with the
/// window off pays only the one cheap config read every tick.
const MESSAGE_RETENTION_SWEEP_INTERVAL: std::time::Duration =
    std::time::Duration::from_secs(6 * 60 * 60);

/// Runs the message retention sweep in the background for the life of the
/// process, on the same detached, best-effort, wait-first model as
/// [`spawn_token_sweep`]. Unlike the other sweeps here, a pruned message is a
/// state change a live connection needs to see now, not merely reclaimed
/// space, so this publishes [`hub::Event::MessageDeleted`] for every message
/// the sweep touched before reclaiming its freed attachment files.
fn spawn_message_retention_sweep(store: store::Store, media: media::Media, hub: hub::Hub) {
    tokio::spawn(async move {
        let mut ticker = tokio::time::interval(MESSAGE_RETENTION_SWEEP_INTERVAL);
        ticker.tick().await;
        loop {
            ticker.tick().await;
            match store.sweep_message_retention().await {
                Ok(swept) if !swept.pruned.is_empty() || swept.ops_reclaimed > 0 => {
                    tracing::info!(
                        pruned = swept.pruned.len(),
                        ops_reclaimed = swept.ops_reclaimed,
                        "pruned messages past the retention window"
                    );
                    for message in swept.pruned {
                        hub.publish(hub::Event::MessageDeleted {
                            channel_id: message.channel_id,
                            message_id: message.message_id,
                            op_seq: message.op_seq,
                        });
                        for hex in message.freed_attachments {
                            if let Err(err) = media.delete_attachment(&hex).await {
                                tracing::warn!(error = %err, attachment = %hex, "failed to delete a retention-freed attachment file");
                            }
                        }
                    }
                }
                Ok(_) => {}
                Err(err) => tracing::warn!(error = %err, "message retention sweep failed"),
            }
        }
    });
}

/// Imports a directory of images as custom emoji, printing a line per file.
///
/// Reads the same `SLIMM_`-prefixed configuration [`run`] does and opens the
/// same database and blob directory, so an operator points it at a deployment
/// by running it where the server runs, with no second place to configure. It
/// is safe to run against a live server: SQLite in WAL mode takes concurrent
/// writers from separate processes, and every emoji is its own transaction.
///
/// Errors if any file did not end up as an emoji, so a script sees a non-zero
/// exit rather than having to parse the report.
pub async fn import_emoji(dir: &std::path::Path) -> anyhow::Result<()> {
    init_tracing_to_stderr();
    let config = config::Config::from_env()?;
    let pool = db::connect(&config).await?;
    let store = store::Store::new(pool);
    let media = media::Media::new(config.attachments_dir.clone(), config.attachment_max_bytes)?
        .with_total_ceiling(config.max_total_attachment_bytes);

    let report = emoji::import::import_directory(&store, &media, dir).await?;
    print!("{report}");

    if !report.is_clean() {
        anyhow::bail!(
            "{} of {} files are not emoji",
            report.unimported(),
            report.files.len()
        );
    }
    Ok(())
}

/// Connects to the local server and confirms `/healthz` returns 200. Used by the
/// container image's healthcheck, since distroless has no shell.
pub async fn healthcheck() -> anyhow::Result<()> {
    // Through Config, so the probe cannot disagree with what the server bound.
    let port = config::Config::from_env()?.port;

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
    init_tracing_to(false);
}

/// Sends logs to stderr instead of stdout.
///
/// The import subcommand prints a machine-readable report on stdout, and at a
/// non-default `SLIMM_LOG` the query logs interleave with it, so anything
/// parsing that report reads corrupted input. Serving keeps stdout, which is
/// what a container's log collector expects.
fn init_tracing_to_stderr() {
    init_tracing_to(true);
}

fn init_tracing_to(stderr: bool) {
    use tracing_subscriber::EnvFilter;
    let filter = EnvFilter::try_from_env("SLIMM_LOG").unwrap_or_else(|_| EnvFilter::new("info"));
    let builder = tracing_subscriber::fmt().with_env_filter(filter);
    if stderr {
        builder.with_writer(std::io::stderr).init();
    } else {
        builder.init();
    }
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
