// SPDX-License-Identifier: AGPL-3.0-only
//! HTTP surface: liveness, version, the auth routes, and the message routes. The
//! WebSocket routes are added as the protocol is built.

use std::time::Duration;

use axum::http::StatusCode;
use axum::{Router, extract::State, routing::get};
use base64::Engine as _;
use base64::engine::general_purpose::STANDARD as BASE64;
use serde::Serialize;
use tower::limit::ConcurrencyLimitLayer;
use tower_http::timeout::{RequestBodyTimeoutLayer, TimeoutLayer};
use tower_http::trace::TraceLayer;

use crate::auth::Auth;
use crate::hub::Hub;
use crate::media::Media;
use crate::push::PushSender;
use crate::ratelimit::RateLimiter;
use crate::store::{JoinPolicy, Store};
use crate::voice::VoiceService;
use error::ApiError;
use extract::{Json, READ, RateLimited};

mod attachments;
mod auth;
mod canvas;
mod canvas_ops;
mod canvas_ops_write;
mod canvas_write;
pub mod capability;
mod channel_order;
mod channels;
mod dms;
mod emoji;
mod error;
mod escalation;
mod extract;
mod invites;
mod members;
mod message_enrich;
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
mod sync_ops;
mod users;
mod voice;
mod ws;

/// The wire-protocol envelope version a client negotiates on connect. Bumped
/// only for a breaking change to the envelope; additive changes keep it.
pub(crate) const PROTOCOL_VERSION: u32 = 1;

/// How long one HTTP request may take before it is abandoned.
///
/// The socket surface has had a bound like this from the start, with a comment
/// saying why: a peer that stops reading could otherwise wedge its task
/// indefinitely. The HTTP surface had none, against a process whose measured
/// idle RSS is 7 MB and whose committed budget is under 30 MB. Generous enough
/// for the heaviest real request (a bundled `/sync`, or an attachment upload at
/// the operator's ceiling over a slow link) and far short of forever.
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// How long a request body may trickle in before it is abandoned.
///
/// Separate from [`REQUEST_TIMEOUT`] because this is the cheaper attack: a
/// request that declares a body and then sends a byte a minute holds a task and
/// its partial buffer for as long as it likes. Caddy's own read-body timeout
/// defaults to unlimited, so the shipped proxy does not cover this either.
const BODY_READ_TIMEOUT: Duration = Duration::from_secs(15);

/// How many HTTP requests may be in flight at once.
///
/// The equivalent of `hub::MAX_CONNECTIONS` for the other surface, and set to
/// the same order of magnitude for the same reason: past some number, admitting
/// more work makes every request slower rather than serving anybody. Requests
/// over it queue rather than fail, so a burst is absorbed and a flood is
/// bounded.
const MAX_INFLIGHT_REQUESTS: usize = 1024;

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
        .merge(channel_order::routes())
        .merge(emoji::routes())
        .merge(invites::routes())
        .merge(members::routes())
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
        // Bounded, and the socket is deliberately outside this: see below.
        .layer(ConcurrencyLimitLayer::new(MAX_INFLIGHT_REQUESTS))
        .layer(TimeoutLayer::with_status_code(
            StatusCode::GATEWAY_TIMEOUT,
            REQUEST_TIMEOUT,
        ))
        .layer(RequestBodyTimeoutLayer::new(BODY_READ_TIMEOUT))
        .merge(ws::routes())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

/// Liveness probe: 200 while the process is serving and the database answers.
///
/// Deliberately the one route that charges no rate limit. A probe is what an
/// orchestrator calls to decide whether this process is alive, and a 429 there
/// reads as unhealthy and gets the container restarted - so throttling it turns
/// a flood into an outage rather than preventing one. It costs one indexed
/// `SELECT 1`, and the request timeout and concurrency limit on the router bound
/// it the same way they bound everything else.
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
    /// The optional features this build serves, read off the router itself.
    /// See [`capability`] for why it is not a list kept by hand.
    capabilities: Vec<&'static str>,
    identity: ServerIdentityDto,
}

/// The capability list for this build, computed on first ask and kept.
///
/// Which routes are mounted is a property of the binary, not of the request
/// or the deployment's configuration, so asking once is the whole answer; the
/// alternative is rebuilding the router on every unauthenticated `/version`.
static CAPABILITIES: std::sync::OnceLock<Vec<&'static str>> = std::sync::OnceLock::new();

async fn capabilities(state: AppState) -> Vec<&'static str> {
    if let Some(cached) = CAPABILITIES.get() {
        return cached.clone();
    }
    let names = capability_names(router(state)).await;
    CAPABILITIES.get_or_init(|| names).clone()
}

/// The `/version` capability list a router serves, as wire names.
///
/// Extracted as its own seam so a test can feed it a router that serves a
/// different set. `capabilities` above is then a trivial one-liner over the
/// real router, but the derivation, empty case included, is provable here
/// against a bare router where a hardcoded `["block", "report"]` would give
/// itself away.
pub async fn capability_names(router: Router) -> Vec<&'static str> {
    capability::served_by(router)
        .await
        .into_iter()
        .map(capability::Capability::wire_name)
        .collect()
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
/// whether this deployment can deliver push at all, what optional features it
/// serves, and the server's trust-on-first-use identity.
///
/// All of it is here rather than behind auth because onboarding needs it
/// before an account exists: someone choosing a LAN-only server should learn
/// their phone will not get notifications while they can still choose
/// differently, someone joining a server with no report or block route should
/// learn there is no recourse here before they commit, and the "connect by
/// address" flow shows the fingerprint before anyone has signed in. All of it
/// reveals deployment configuration only, never user data.
async fn version(
    _limited: RateLimited<READ>,
    State(state): State<AppState>,
) -> Result<Json<Version>, ApiError> {
    let identity = state.store.server_identity().await?;
    Ok(Json(Version {
        name: "slim-m",
        version: env!("CARGO_PKG_VERSION"),
        protocol: PROTOCOL_VERSION,
        push_enabled: state.push.is_enabled(),
        invite_required: state.store.join_policy().await? == JoinPolicy::Invite,
        capabilities: capabilities(state).await,
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
