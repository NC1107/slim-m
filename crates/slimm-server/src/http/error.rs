// SPDX-License-Identifier: AGPL-3.0-only
//! The shared HTTP error type and its status mapping. Every route returns this
//! so error responses are uniform across the API.

use axum::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;

use crate::auth::HashError;
use crate::store::{OpenError, PushError, SendError};

pub(crate) enum ApiError {
    BadRequest(&'static str),
    Unauthorized,
    Forbidden,
    NotFound(&'static str),
    Conflict(&'static str),
    TooManyRequests,
    /// The deployment does not offer this feature at all, as opposed to
    /// offering it and being briefly unable to serve it. Distinct from
    /// [`ApiError::Unavailable`] so a client can hide the feature rather than
    /// showing it and retrying forever.
    NotConfigured(&'static str),
    Unavailable,
    Internal,
}

#[derive(Serialize)]
struct ErrorBody {
    error: &'static str,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error) = match self {
            ApiError::BadRequest(message) => (StatusCode::BAD_REQUEST, message),
            ApiError::Unauthorized => (StatusCode::UNAUTHORIZED, "invalid credentials"),
            ApiError::Forbidden => (StatusCode::FORBIDDEN, "insufficient permissions"),
            ApiError::NotFound(message) => (StatusCode::NOT_FOUND, message),
            ApiError::Conflict(message) => (StatusCode::CONFLICT, message),
            ApiError::TooManyRequests => (StatusCode::TOO_MANY_REQUESTS, "slow down and retry"),
            ApiError::NotConfigured(message) => (StatusCode::NOT_IMPLEMENTED, message),
            ApiError::Unavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "server busy, retry shortly",
            ),
            ApiError::Internal => (StatusCode::INTERNAL_SERVER_ERROR, "internal error"),
        };
        (status, Json(ErrorBody { error })).into_response()
    }
}

impl From<anyhow::Error> for ApiError {
    fn from(err: anyhow::Error) -> Self {
        tracing::error!(error = %err, "request failed");
        ApiError::Internal
    }
}

impl From<HashError> for ApiError {
    fn from(err: HashError) -> Self {
        match err {
            // Shed load past the hashing deadline instead of hanging the caller.
            HashError::Busy => ApiError::Unavailable,
            HashError::Internal(e) => {
                tracing::error!(error = %e, "password hashing failed");
                ApiError::Internal
            }
        }
    }
}

impl From<SendError> for ApiError {
    fn from(err: SendError) -> Self {
        match err {
            SendError::IdConflict => ApiError::Conflict("message id already used"),
            SendError::AttachmentNotFound => {
                ApiError::BadRequest("attachment not found; upload it first")
            }
            SendError::Internal(e) => {
                tracing::error!(error = %e, "message send failed");
                ApiError::Internal
            }
        }
    }
}

impl From<PushError> for ApiError {
    fn from(err: PushError) -> Self {
        match err {
            // The caller's own device vanished mid-request (signed out from
            // elsewhere, or the account was deleted concurrently).
            PushError::NotFound => ApiError::NotFound("device not found"),
            PushError::Internal(e) => {
                tracing::error!(error = %e, "push registration failed");
                ApiError::Internal
            }
        }
    }
}

impl From<OpenError> for ApiError {
    fn from(err: OpenError) -> Self {
        match err {
            // The account vanished mid-login; treat it as a failed credential.
            OpenError::AccountGone => ApiError::Unauthorized,
            OpenError::Internal(e) => {
                tracing::error!(error = %e, "opening a session failed");
                ApiError::Internal
            }
        }
    }
}
