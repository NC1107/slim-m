// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! `GET /metrics`: process resident memory, request counts by rate-limit
//! class, currently open WebSocket connections, and whether the configured
//! SFU answers - as Prometheus text exposition format.
//!
//! Built to close the exact gap CLAUDE.md records: LiveKit crashlooped for
//! half an hour behind a `voice enabled` line that only ever reports the
//! server's own config, never whether the SFU it names actually answers.
//! `compose-smoke` now checks that by hand once, at deploy time; this makes
//! it an ongoing, scrapable signal.
//!
//! **Auth**: gated on an authenticated session holding `MANAGE_SERVER`, the
//! same bit `/space/analytics` already gates on, rather than left open the
//! way `/version` is. `/version` discloses a handful of deployment-wide
//! facts an unauthenticated caller needs before an account exists; this
//! discloses traffic volume by class and connection counts, which is a
//! member-count-adjacent signal about a specific self-hosted community, not
//! the kind of thing this project leaves unauthenticated. There is no
//! service-account or API-key concept in this server, so an admin's own
//! session token is what a Prometheus scrape has to carry; a dedicated
//! scrape credential is a reasonable follow-up if that friction turns out
//! to matter, not built here.
//!
//! **Rate limit**: `Class::Write`, not the generous `Class::AuthedRead` most
//! authenticated GETs use, because `write_voice` below makes a real,
//! uncached outbound call to the configured SFU on every scrape - a cheap
//! list read this is not, and a scrape interval short enough to blow
//! `Write`'s budget is already misconfigured against the SFU it is probing.
//!
//! **No metrics crate.** `docs/dependencies.md` already declines a charting
//! package for three bar charts on the grounds that a small, bespoke output
//! is a function, not a dependency; four gauges and two counter families
//! hand-rolled as text is smaller still, and a crate like `prometheus` or
//! `metrics` would bring its own registry, encoder, and (for `metrics`) an
//! exporter trait object this server has no other use for.

use axum::Router;
use axum::extract::State;
use axum::http::request::Parts;
use axum::http::{HeaderValue, header};
use axum::response::{IntoResponse, Response};
use axum::routing::get;

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, enforce};
use crate::permissions::Permissions;
use crate::process_metrics::current_rss_bytes;
use crate::ratelimit::Class;

/// The metrics route, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new().route("/metrics", get(metrics))
}

async fn metrics(
    State(state): State<AppState>,
    parts: Parts,
    Authed(ctx): Authed,
) -> Result<Response, ApiError> {
    // Write, not AuthedRead: write_voice probes the SFU live on every call.
    enforce(&state, &parts, Some(&ctx), Class::Write)?;
    let permissions = state.store.base_permissions(ctx.user_id).await?;
    if !permissions.contains(Permissions::MANAGE_SERVER) {
        return Err(ApiError::Forbidden);
    }

    let mut body = String::new();
    write_memory(&mut body);
    write_requests(&mut body, &state);
    write_connections(&mut body, &state);
    write_voice(&mut body, &state).await;

    let mut response = body.into_response();
    response.headers_mut().insert(
        header::CONTENT_TYPE,
        HeaderValue::from_static("text/plain; version=0.0.4; charset=utf-8"),
    );
    Ok(response)
}

fn write_memory(out: &mut String) {
    out.push_str(
        "# HELP slimm_process_resident_memory_bytes Resident memory of this server process.\n",
    );
    out.push_str("# TYPE slimm_process_resident_memory_bytes gauge\n");
    match current_rss_bytes() {
        Some(bytes) => out.push_str(&format!("slimm_process_resident_memory_bytes {bytes}\n")),
        // `NaN` is a legal Prometheus float: this platform genuinely cannot answer, not a zero.
        None => out.push_str("slimm_process_resident_memory_bytes NaN\n"),
    }
}

/// Requests admitted and refused per rate-limit class - the closest thing
/// this server has to a per-route request counter, and reused rather than
/// duplicated: every authenticated write, read, upload, and canvas action
/// already passes through one of these classes to be charged at all, so
/// counting there covers message and request volume alike with no second
/// counter to keep in step.
fn write_requests(out: &mut String, state: &AppState) {
    let counts = state.limiter.counts();

    out.push_str(
        "# HELP slimm_requests_total Requests admitted per rate-limit class since process start.\n",
    );
    out.push_str("# TYPE slimm_requests_total counter\n");
    for (class, count) in &counts {
        out.push_str(&format!(
            "slimm_requests_total{{class=\"{}\"}} {}\n",
            class.label(),
            count.admitted
        ));
    }
    out.push_str(
        "# HELP slimm_requests_refused_total Requests refused for exceeding their class's rate-limit budget.\n",
    );
    out.push_str("# TYPE slimm_requests_refused_total counter\n");
    for (class, count) in &counts {
        out.push_str(&format!(
            "slimm_requests_refused_total{{class=\"{}\"}} {}\n",
            class.label(),
            count.refused
        ));
    }
}

fn write_connections(out: &mut String, state: &AppState) {
    out.push_str("# HELP slimm_websocket_connections Currently open WebSocket connections.\n");
    out.push_str("# TYPE slimm_websocket_connections gauge\n");
    out.push_str(&format!(
        "slimm_websocket_connections {}\n",
        state.hub.connection_count()
    ));
}

/// The SFU gauges. `slimm_livekit_reachable` is emitted only when an SFU is
/// configured at all - a text-only deployment has nothing to be unreachable,
/// and a bare `0` there would read as an outage rather than a choice.
async fn write_voice(out: &mut String, state: &AppState) {
    out.push_str(
        "# HELP slimm_livekit_configured Whether this deployment has an SFU configured.\n",
    );
    out.push_str("# TYPE slimm_livekit_configured gauge\n");
    out.push_str(&format!(
        "slimm_livekit_configured {}\n",
        i32::from(state.voice.is_enabled())
    ));

    if let Some(reachable) = state.voice.probe_reachable().await {
        out.push_str(
            "# HELP slimm_livekit_reachable Whether the configured SFU answered the last reachability probe.\n",
        );
        out.push_str("# TYPE slimm_livekit_reachable gauge\n");
        out.push_str(&format!(
            "slimm_livekit_reachable {}\n",
            i32::from(reachable)
        ));
    }
}
