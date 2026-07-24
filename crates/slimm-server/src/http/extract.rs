// SPDX-License-Identifier: AGPL-3.0-only
//! The bearer-token authentication extractor, shared by every authenticated
//! route.

use axum::extract::FromRequestParts;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;

use super::AppState;
use super::error::ApiError;
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
