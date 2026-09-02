// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The shared HTTP error type and its status mapping. Every route returns this
//! so error responses are uniform across the API, and so do axum's own
//! extractor rejections (malformed JSON, a bad query string, an oversized
//! body): [`super::extract::Json`], [`super::extract::Query`] and
//! [`super::extract::Bytes`] map them here rather than leaving axum's default
//! plain-text body.

use std::borrow::Cow;
use std::error::Error as StdError;

use axum::Json;
use axum::extract::rejection::{BytesRejection, JsonRejection, QueryRejection};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Serialize;

use crate::auth::HashError;
use crate::store::{CreateChannelError, CreateRoleError, OpenError, PushError, SendError};

/// The fixed body a 500 always carries, never a stack trace or type path.
///
/// Named rather than inlined so a unit test can cross-check it against
/// `tests/fixtures/onboarding_error_strings.json`, the fixture the client's
/// own onboarding snapshot tests read so their fixture text cannot drift
/// from what a real 500 actually sends.
const INTERNAL_ERROR_MESSAGE: &str = "internal error";

pub(crate) enum ApiError {
    BadRequest(&'static str),
    /// Like [`ApiError::BadRequest`], but the message names something only
    /// known at request time (a missing field, an unparsable query key) and
    /// so cannot be `&'static str`.
    BadRequestDetail(String),
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
    PayloadTooLarge,
    /// The deployment has no room left for what this would store.
    ///
    /// Deliberately not [`ApiError::PayloadTooLarge`], which already means "your
    /// file is over the per-upload limit". An operator reading a user's
    /// screenshot needs to tell "make it smaller" apart from "the volume is
    /// full", and the two have different fixes: one is the sender's, the other
    /// is the operator's.
    InsufficientStorage,
    Internal,
}

#[derive(Serialize)]
struct ErrorBody {
    error: Cow<'static, str>,
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, error): (StatusCode, Cow<'static, str>) = match self {
            ApiError::BadRequest(message) => (StatusCode::BAD_REQUEST, message.into()),
            ApiError::BadRequestDetail(message) => (StatusCode::BAD_REQUEST, message.into()),
            ApiError::Unauthorized => (StatusCode::UNAUTHORIZED, "invalid credentials".into()),
            ApiError::Forbidden => (StatusCode::FORBIDDEN, "insufficient permissions".into()),
            ApiError::NotFound(message) => (StatusCode::NOT_FOUND, message.into()),
            ApiError::Conflict(message) => (StatusCode::CONFLICT, message.into()),
            ApiError::TooManyRequests => {
                (StatusCode::TOO_MANY_REQUESTS, "slow down and retry".into())
            }
            ApiError::NotConfigured(message) => (StatusCode::NOT_IMPLEMENTED, message.into()),
            ApiError::Unavailable => (
                StatusCode::SERVICE_UNAVAILABLE,
                "server busy, retry shortly".into(),
            ),
            ApiError::PayloadTooLarge => (
                StatusCode::PAYLOAD_TOO_LARGE,
                "request body exceeds the size limit".into(),
            ),
            ApiError::InsufficientStorage => (
                StatusCode::INSUFFICIENT_STORAGE,
                "this deployment has no storage left for new uploads".into(),
            ),
            ApiError::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                INTERNAL_ERROR_MESSAGE.into(),
            ),
        };
        (status, Json(ErrorBody { error })).into_response()
    }
}

/// The rejection's own explanation one layer in, skipping axum's added
/// wrapper text (`"Failed to ... : "`) to reach what the parser itself named:
/// a missing field or a syntax position, never the request body or a Rust
/// type path.
fn rejection_detail(err: &(dyn StdError + 'static)) -> String {
    match err.source() {
        Some(source) => source.to_string(),
        None => err.to_string(),
    }
}

/// Oversized-body rejections keep their distinct status; everything else
/// about a malformed extractor is a 400 with the parser's own detail.
fn from_rejection(status: StatusCode, detail: String) -> ApiError {
    if status == StatusCode::PAYLOAD_TOO_LARGE {
        ApiError::PayloadTooLarge
    } else {
        ApiError::BadRequestDetail(detail)
    }
}

impl From<JsonRejection> for ApiError {
    fn from(rejection: JsonRejection) -> Self {
        from_rejection(rejection.status(), rejection_detail(&rejection))
    }
}

impl From<QueryRejection> for ApiError {
    fn from(rejection: QueryRejection) -> Self {
        from_rejection(rejection.status(), rejection_detail(&rejection))
    }
}

impl From<BytesRejection> for ApiError {
    fn from(rejection: BytesRejection) -> Self {
        from_rejection(rejection.status(), rejection_detail(&rejection))
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

impl From<CreateChannelError> for ApiError {
    fn from(err: CreateChannelError) -> Self {
        match err {
            CreateChannelError::IdConflict => {
                ApiError::Conflict("channel id already used by a dm or a thread")
            }
            CreateChannelError::UnknownCategory => {
                ApiError::BadRequest("category_id must name a category that exists")
            }
            CreateChannelError::Internal(e) => {
                tracing::error!(error = %e, "channel create failed");
                ApiError::Internal
            }
        }
    }
}

impl From<CreateRoleError> for ApiError {
    fn from(err: CreateRoleError) -> Self {
        match err {
            CreateRoleError::IdConflict => {
                ApiError::Conflict("role id already used by the @everyone role")
            }
            CreateRoleError::Internal(e) => {
                tracing::error!(error = %e, "role create failed");
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
            SendError::InvalidReplyTarget => ApiError::BadRequest(
                "reply_to_id must name a live or deleted message in this channel",
            ),
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
            // 403 because the credentials were right; retrying cannot help.
            OpenError::Removed => ApiError::Forbidden,
            OpenError::Internal(e) => {
                tracing::error!(error = %e, "opening a session failed");
                ApiError::Internal
            }
        }
    }
}

#[cfg(test)]
mod tests {
    /// Cross-checked against the same string in `client/packages/app/test/
    /// support/onboarding_error_strings.dart`, both read from `tests/
    /// fixtures/onboarding_error_strings.json` - editing the wire text
    /// on one side without the other fails whichever side the fixture
    /// no longer matches.
    #[test]
    fn internal_error_message_matches_the_shared_onboarding_fixture() {
        let fixture = load_fixture();
        assert_eq!(super::INTERNAL_ERROR_MESSAGE, fixture.internal_error);
    }

    #[derive(serde::Deserialize)]
    struct OnboardingErrorStrings {
        internal_error: String,
    }

    fn load_fixture() -> OnboardingErrorStrings {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/onboarding_error_strings.json");
        let raw = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("reading {}: {e}", path.display()));
        serde_json::from_str(&raw).expect("onboarding_error_strings.json must be valid JSON")
    }
}
