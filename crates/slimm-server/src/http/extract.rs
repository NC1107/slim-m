// SPDX-License-Identifier: AGPL-3.0-only
//! The bearer-token authentication extractor, shared by every authenticated
//! route, plus the `Json`, `Query` and `Bytes` extractors every handler in
//! this crate uses in their place: same wire behaviour as axum's own, but a
//! malformed or oversized request rejects with [`ApiError`] instead of
//! axum's default plain text.

use std::net::SocketAddr;

use axum::extract::{ConnectInfo, FromRequest, FromRequestParts, Request};
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use serde::de::DeserializeOwned;

use super::AppState;
use super::error::ApiError;
use crate::ratelimit::Class;
use crate::store::SessionContext;

/// The session a request is authenticated as, resolved from its bearer access
/// token. Rejects with 401 when the header is absent or the token is invalid.
pub(crate) struct Authed(pub(crate) SessionContext);

impl FromRequestParts<AppState> for Authed {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let token = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|value| value.to_str().ok())
            .and_then(|header| header.strip_prefix("Bearer "))
            .map(str::to_owned)
            .ok_or(ApiError::Unauthorized)?;
        let ctx = state
            .store
            .authenticate(&token)
            .await?
            .ok_or(ApiError::Unauthorized)?;
        Ok(Authed(ctx))
    }
}

/// The caller's identity for rate-limiting purposes: the authenticated user when
/// there is one, otherwise the peer address. Authenticated callers are keyed by
/// user so a limit follows the account across devices and networks, rather than
/// being shed by reconnecting from a new address.
///
/// The unauthenticated key is the peer address unless the operator has said how
/// many proxies sit in front of this server (`trusted_hops`). A forwarded header
/// is unsigned and anyone may send one, so believing it by default would let a
/// caller mint a fresh bucket per request.
///
/// What makes a non-zero setting safe is counting from the *right*. A proxy
/// appends the address it saw, so the rightmost entry was written by the nearest
/// proxy and each step left is one hop further out. A caller can prepend as many
/// entries as they like and never reach the slot `trusted_hops` selects.
///
/// This matters more than it looks: with no setting and a reverse proxy in
/// front - which is what `deploy/` ships - every unauthenticated caller in the
/// world shares one bucket, so one client can hold the password bucket empty and
/// nobody can sign in. Caddy has no built-in per-IP limit to do this instead.
pub(crate) fn limit_key(
    parts: &Parts,
    ctx: Option<&SessionContext>,
    trusted_hops: usize,
) -> String {
    if let Some(ctx) = ctx {
        return format!("u:{}", ctx.user_id);
    }
    if trusted_hops > 0
        && let Some(addr) = forwarded_for(parts, trusted_hops)
    {
        return format!("ip:{addr}");
    }
    parts
        .extensions
        .get::<ConnectInfo<SocketAddr>>()
        .map(|ConnectInfo(addr)| format!("ip:{}", addr.ip()))
        .unwrap_or_else(|| "ip:unknown".to_owned())
}

/// The address `hops` from the right of `X-Forwarded-For`, or `None` when the
/// header is absent or too short to have one.
///
/// Too short is deliberately `None` rather than the leftmost entry: falling back
/// to whatever the client sent is exactly the spoof this counts from the right to
/// avoid, and the peer address is a safe answer where this has none.
fn forwarded_for(parts: &Parts, hops: usize) -> Option<String> {
    let header = parts.headers.get("x-forwarded-for")?.to_str().ok()?;
    let addrs: Vec<&str> = header
        .split(',')
        .map(str::trim)
        .filter(|entry| !entry.is_empty())
        .collect();
    addrs
        .len()
        .checked_sub(hops)
        .and_then(|index| addrs.get(index))
        .map(|addr| (*addr).to_owned())
}

/// Enforces the rate limit for `class`, keyed by the caller.
pub(crate) fn enforce(
    state: &AppState,
    parts: &Parts,
    ctx: Option<&SessionContext>,
    class: Class,
) -> Result<(), ApiError> {
    let key = limit_key(parts, ctx, state.limiter.trusted_hops());
    if state.limiter.check(class, &key) {
        Ok(())
    } else {
        Err(ApiError::TooManyRequests)
    }
}

/// An unauthenticated request that has passed the rate limit for its class.
/// Used by the password and refresh endpoints, which are reachable by anyone.
pub(crate) struct RateLimited<const C: u8>;

/// Class codes for [`RateLimited`] and [`AuthedLimited`], since const generics
/// cannot take an enum.
pub(crate) const PASSWORD: u8 = 0;
pub(crate) const REFRESH: u8 = 1;
pub(crate) const INVITE_CHECK: u8 = 2;
pub(crate) const WRITE: u8 = 3;
pub(crate) const READ: u8 = 4;
pub(crate) const UPLOAD: u8 = 5;
pub(crate) const CANVAS: u8 = 6;
pub(crate) const ASSET: u8 = 7;
pub(crate) const GIF: u8 = 8;

/// Panics on an unknown code rather than falling back.
///
/// It used to end `_ => Class::Refresh`, which meant a new code compiled clean
/// and silently charged a budget twenty times looser on refill than Password's -
/// on endpoints that are unauthenticated and expensive. There is no safe default
/// here, so there is no default: every code is named, and the panic is
/// unreachable for any code this module defines.
fn class_of(code: u8) -> Class {
    match code {
        PASSWORD => Class::Password,
        REFRESH => Class::Refresh,
        INVITE_CHECK => Class::InviteCheck,
        WRITE => Class::Write,
        READ => Class::Read,
        UPLOAD => Class::Upload,
        CANVAS => Class::Canvas,
        ASSET => Class::Asset,
        GIF => Class::Gif,
        other => unreachable!("no rate-limit class for code {other}"),
    }
}

impl<const C: u8> FromRequestParts<AppState> for RateLimited<C> {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        enforce(state, parts, None, class_of(C))?;
        Ok(RateLimited)
    }
}

/// An authenticated request that has also paid its rate limit.
///
/// One extractor rather than the three-part idiom it replaces (`Authed(ctx)`
/// plus `parts: Parts` plus a remembered `enforce(...)` call), because the
/// charge being a line somebody has to remember is exactly how it went missing:
/// eight routes charged nothing, and this project had already found and fixed
/// the same omission once before on message edit.
///
/// Declaring the class in the signature makes "no limit" a visible, reviewable
/// choice instead of an absence. It also drops the `parts: Parts` argument,
/// which axum satisfies by cloning every header on the request.
pub(crate) struct AuthedLimited<const C: u8>(pub(crate) SessionContext);

impl<const C: u8> FromRequestParts<AppState> for AuthedLimited<C> {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        // Authenticate first: the charge belongs on the account, not an address.
        let Authed(ctx) = Authed::from_request_parts(parts, state).await?;
        enforce(state, parts, Some(&ctx), class_of(C))?;
        Ok(AuthedLimited(ctx))
    }
}

/// A JSON request body, and a JSON response: a drop-in for [`axum::Json`]
/// usable in both positions, so swapping the import is the whole migration.
pub(crate) struct Json<T>(pub(crate) T);

impl<T: DeserializeOwned> FromRequest<AppState> for Json<T> {
    type Rejection = ApiError;

    async fn from_request(req: Request, state: &AppState) -> Result<Self, Self::Rejection> {
        let axum::Json(value) = axum::Json::<T>::from_request(req, state).await?;
        Ok(Json(value))
    }
}

impl<T: Serialize> IntoResponse for Json<T> {
    fn into_response(self) -> Response {
        axum::Json(self.0).into_response()
    }
}

/// A query-string extractor: a drop-in for [`axum::extract::Query`].
pub(crate) struct Query<T>(pub(crate) T);

impl<T: DeserializeOwned> FromRequestParts<AppState> for Query<T> {
    type Rejection = ApiError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let axum::extract::Query(value) =
            axum::extract::Query::<T>::from_request_parts(parts, state).await?;
        Ok(Query(value))
    }
}

/// The raw request body: a drop-in for [`axum::body::Bytes`], used by the
/// three routes that accept a binary upload rather than JSON.
pub(crate) struct Bytes(pub(crate) axum::body::Bytes);

impl FromRequest<AppState> for Bytes {
    type Rejection = ApiError;

    async fn from_request(req: Request, state: &AppState) -> Result<Self, Self::Rejection> {
        let bytes = axum::body::Bytes::from_request(req, state).await?;
        Ok(Bytes(bytes))
    }
}

#[cfg(test)]
mod tests {
    use super::forwarded_for;
    use axum::http::Request;
    use axum::http::request::Parts;

    fn parts(xff: Option<&str>) -> Parts {
        let mut builder = Request::builder();
        if let Some(value) = xff {
            builder = builder.header("x-forwarded-for", value);
        }
        builder.body(()).unwrap().into_parts().0
    }

    #[test]
    fn a_missing_header_selects_nothing() {
        assert_eq!(forwarded_for(&parts(None), 1), None);
    }

    /// The client is counted `hops` from the right, so entries a caller
    /// prepends can never reach the selected slot - the whole reason the count
    /// is from the right and not the left.
    #[test]
    fn a_prepended_entry_cannot_change_the_selected_address() {
        assert_eq!(
            forwarded_for(&parts(Some("2.2.2.2")), 1).as_deref(),
            Some("2.2.2.2")
        );
        assert_eq!(
            forwarded_for(&parts(Some("spoofed, 2.2.2.2")), 1).as_deref(),
            Some("2.2.2.2")
        );
    }

    #[test]
    fn the_hop_count_is_taken_from_the_right() {
        // Two trusted hops over "a, b, c" is two from the right: "b".
        assert_eq!(
            forwarded_for(&parts(Some("a, b, c")), 2).as_deref(),
            Some("b")
        );
    }

    /// A header with fewer entries than trusted hops selects nothing rather
    /// than wrapping to the leftmost, so a short forged header falls back to
    /// the socket peer instead of being believed.
    #[test]
    fn fewer_entries_than_hops_selects_nothing() {
        assert_eq!(forwarded_for(&parts(Some("only")), 2), None);
        assert_eq!(forwarded_for(&parts(Some("only")), 0), None);
    }

    /// A trailing comma is dropped, not counted: without that, one trusted hop
    /// over `"2.2.2.2, "` would select the empty entry and key everyone who
    /// sends a trailing comma into one bucket.
    #[test]
    fn empty_and_whitespace_entries_are_dropped_before_counting() {
        assert_eq!(
            forwarded_for(&parts(Some("2.2.2.2, ")), 1).as_deref(),
            Some("2.2.2.2")
        );
        assert_eq!(
            forwarded_for(&parts(Some("a,, b")), 1).as_deref(),
            Some("b")
        );
    }
}
