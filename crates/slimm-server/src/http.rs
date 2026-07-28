// SPDX-License-Identifier: AGPL-3.0-only
//! HTTP surface: liveness, version, the auth routes, and the message routes. The
//! WebSocket routes are added as the protocol is built.

use axum::{Json, Router, extract::State, routing::get};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde::Serialize;
use tower_http::trace::TraceLayer;

use crate::auth::Auth;
use crate::hub::Hub;
use crate::media::Media;
use crate::push::PushSender;
use crate::ratelimit::RateLimiter;
use crate::store::{JoinPolicy, Store};
use crate::voice::VoiceService;
use error::ApiError;

mod attachments;
mod auth;
mod canvas;
mod channels;
mod dms;
mod emoji;
mod error;
mod extract;
mod invites;
mod messages;
mod overwrites;
mod pins;
mod polls;
mod presence;
mod push;
mod reactions;
mod recovery;
mod reports;
mod roles;
mod safety;
mod search;
mod space;
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
    pub media: Media,
}

/// Builds the router over the shared application state.
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/version", get(version))
        .merge(auth::routes())
        .merge(canvas::routes())
        .merge(channels::routes())
        .merge(emoji::routes())
        .merge(invites::routes())
        .merge(messages::routes())
        .merge(overwrites::routes())
        .merge(presence::routes())
        .merge(reactions::routes())
        .merge(push::routes())
        .merge(pins::routes())
        .merge(recovery::routes())
        .merge(reports::routes())
        .merge(roles::routes())
        .merge(safety::routes())
        .merge(dms::routes())
        .merge(search::routes())
        .merge(space::routes())
        .merge(sync::routes())
        .merge(voice::routes())
        .merge(polls::routes())
        .merge(users::routes())
        .merge(attachments::routes(state.media.max_attachment_bytes()))
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
    /// Whether creating an account here needs an invite code. Onboarding
    /// needs this before an account exists, so it rides on /version.
    invite_required: bool,
    identity: ServerIdentityDto,
}

/// The wire shape of [`crate::identity::ServerIdentity`]. Kept as a distinct
/// DTO (rather than deriving `Serialize` on the domain type itself) so the
/// domain module never has to think about base64 or hex, only bytes.
#[derive(Serialize)]
struct ServerIdentityDto {
    /// Standard base64 of the 32-byte Ed25519 public key. This, not
    /// `fingerprint`, is what a client should actually pin and compare
    /// byte-for-byte on every later connect.
    public_key: String,
    /// 32 lowercase hex characters (a truncated SHA-256 of the public key),
    /// with no separators, for a client to store or compare programmatically.
    fingerprint: String,
    /// The same fingerprint, split into eight 4-character hex groups, ready
    /// for the onboarding design's two-rows-of-four display.
    fingerprint_groups: Vec<String>,
    /// Four indices into the client's six-entry cursor colour palette
    /// (`AppCanvasColors.cursors`), deterministically derived from the
    /// fingerprint, for an at-a-glance colour strip alongside the hex.
    color_strip: [u8; 4],
}

/// Build version, the wire-protocol envelope version a client negotiates,
/// whether this deployment can deliver push at all, and the server's
/// trust-on-first-use identity.
///
/// Push state and identity are both here rather than behind auth because
/// onboarding needs them before an account exists: someone choosing a
/// LAN-only server should learn their phone will not get notifications
/// while they can still choose differently, and the "connect by address"
/// flow shows the fingerprint before anyone has signed in. Both reveal only
/// deployment configuration, never user data.
async fn version(State(state): State<AppState>) -> Result<Json<Version>, ApiError> {
    let identity = state.store.server_identity().await?;
    Ok(Json(Version {
        name: "slim-m",
        version: env!("CARGO_PKG_VERSION"),
        protocol: PROTOCOL_VERSION,
        push_enabled: state.push.is_enabled(),
        invite_required: state.store.join_policy().await? == JoinPolicy::Invite,
        identity: ServerIdentityDto {
            public_key: BASE64.encode(identity.public_key()),
            fingerprint: identity.fingerprint_hex(),
            fingerprint_groups: identity.fingerprint_groups(),
            color_strip: identity.color_strip(),
        },
    }))
}

/// Minimal error so a failed liveness check returns 503 rather than panicking.
struct StatusError;

impl axum::response::IntoResponse for StatusError {
    fn into_response(self) -> axum::response::Response {
        (axum::http::StatusCode::SERVICE_UNAVAILABLE, "unavailable").into_response()
    }
}
