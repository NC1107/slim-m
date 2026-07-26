// SPDX-License-Identifier: AGPL-3.0-only
//! HTTP surface: liveness, version, the auth routes, and the message routes. The
//! WebSocket routes are added as the protocol is built.

use axum::{Json, Router, extract::State, routing::get};
use serde::Serialize;
use tower_http::trace::TraceLayer;

use crate::auth::Auth;
use crate::hub::Hub;
use crate::push::PushSender;
use crate::ratelimit::RateLimiter;
use crate::store::Store;
use crate::voice::VoiceService;

mod auth;
mod channels;
mod error;
mod extract;
mod invites;
mod messages;
mod overwrites;
mod push;
mod reactions;
mod recovery;
mod reports;
mod roles;
mod safety;
mod search;
mod sync;
mod users;
mod voice;
mod ws;

/// The wire-protocol envelope version a client negotiates on connect. Bumped
/// only for a breaking change to the envelope; additive changes keep it.
pub(crate) const PROTOCOL_VERSION: u32 = 1;

/// What every handler shares: the persistence layer, the auth service, and the
/// fan-out hub. Cloning is cheap (a pool handle and a couple of `Arc`s).
#[derive(Clone)]
pub struct AppState {
    pub store: Store,
    pub auth: Auth,
    pub hub: Hub,
    pub limiter: RateLimiter,
    pub push: PushSender,
    pub voice: VoiceService,
}

/// Builds the router over the shared application state.
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/version", get(version))
        .merge(auth::routes())
        .merge(channels::routes())
        .merge(invites::routes())
        .merge(messages::routes())
        .merge(overwrites::routes())
        .merge(reactions::routes())
        .merge(push::routes())
        .merge(recovery::routes())
        .merge(reports::routes())
        .merge(roles::routes())
        .merge(safety::routes())
        .merge(search::routes())
        .merge(sync::routes())
        .merge(voice::routes())
        .merge(users::routes())
        .merge(ws::routes())
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
    push_enabled: bool,
}

/// Build version, the wire-protocol envelope version a client negotiates, and
/// whether this deployment can deliver push at all.
///
/// Push state is here rather than behind auth because onboarding needs it
/// before an account exists: someone choosing a LAN-only server should learn
/// their phone will not get notifications while they can still choose
/// differently. It reveals only deployment configuration, not user data.
async fn version(State(state): State<AppState>) -> Json<Version> {
    Json(Version {
        name: "slim-m",
        version: env!("CARGO_PKG_VERSION"),
        protocol: PROTOCOL_VERSION,
        push_enabled: state.push.is_enabled(),
    })
}

/// Minimal error so a failed liveness check returns 503 rather than panicking.
struct StatusError;

impl axum::response::IntoResponse for StatusError {
    fn into_response(self) -> axum::response::Response {
        (axum::http::StatusCode::SERVICE_UNAVAILABLE, "unavailable").into_response()
    }
}
