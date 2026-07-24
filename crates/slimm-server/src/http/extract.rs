// SPDX-License-Identifier: AGPL-3.0-only
//! The bearer-token authentication extractor, shared by every authenticated
//! route.

use std::net::SocketAddr;

use axum::extract::{ConnectInfo, FromRequestParts};
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;

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
pub(crate) fn limit_key(parts: &Parts, ctx: Option<&SessionContext>) -> String {
    if let Some(ctx) = ctx {
        return format!("u:{}", ctx.user_id);
    }
    // Deliberately the peer address, not a forwarded header: this server may sit
    // behind a proxy it does not control, and a spoofable header would let a
    // caller mint unlimited keys. A reverse proxy that terminates for real
    // clients should apply its own per-IP limit as well.
    parts
        .extensions
        .get::<ConnectInfo<SocketAddr>>()
        .map(|ConnectInfo(addr)| format!("ip:{}", addr.ip()))
        .unwrap_or_else(|| "ip:unknown".to_owned())
}

/// Enforces the rate limit for `class`, keyed by the caller.
pub(crate) fn enforce(
    state: &AppState,
    parts: &Parts,
    ctx: Option<&SessionContext>,
    class: Class,
) -> Result<(), ApiError> {
    if state.limiter.check(class, &limit_key(parts, ctx)) {
        Ok(())
    } else {
        Err(ApiError::TooManyRequests)
    }
}

/// An unauthenticated request that has passed the rate limit for its class.
/// Used by the password and refresh endpoints, which are reachable by anyone.
pub(crate) struct RateLimited<const C: u8>;

/// Class codes for [`RateLimited`], since const generics cannot take an enum.
pub(crate) const PASSWORD: u8 = 0;
pub(crate) const REFRESH: u8 = 1;

fn class_of(code: u8) -> Class {
    match code {
        PASSWORD => Class::Password,
        _ => Class::Refresh,
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
