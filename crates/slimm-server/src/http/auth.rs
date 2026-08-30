// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Auth HTTP routes: register, login, refresh, connect-ticket, and logout.
//!
//! The durable mechanics live in [`crate::store`] and [`crate::auth`]; this
//! module is the thin REST skin over them, plus input validation, the bearer
//! extractor, and the error-to-status mapping.

use axum::Router;
use axum::extract::{DefaultBodyLimit, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::routing::{delete, post};
use serde::{Deserialize, Serialize};

use super::AppState;
use super::error::ApiError;
use super::extract::{Authed, AuthedLimited, Json, PASSWORD, REFRESH, RateLimited, WRITE, enforce};
use crate::hub::Event;
use crate::ratelimit::Class;
use crate::store::DeleteAccountError;
use crate::store::{Bootstrap, IssuedTokens, JoinPolicy, RefreshOutcome, RegisterError};

/// Auth payloads are a handful of short fields; cap the body well below any
/// realistic request so an oversized body is rejected before it is buffered.
const AUTH_BODY_LIMIT: usize = 4 * 1024;

/// Said the same way whether the code was missing up front or the deployment
/// was claimed mid-request, so the client has one string to react to.
const INVITE_REQUIRED: &str = "an invite code is required to join this server";

/// The auth routes, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/refresh", post(refresh))
        .route("/auth/ws-ticket", post(ws_ticket))
        .route("/auth/logout", post(logout))
        .route("/account", delete(delete_account))
        .layer(DefaultBodyLimit::max(AUTH_BODY_LIMIT))
}

// --- Wire types ---

#[derive(Deserialize)]
struct RegisterRequest {
    username: String,
    display_name: String,
    password: String,
    device_name: String,
    /// Required once the deployment has been claimed; ignored before that,
    /// since the first account is the one that claims it and there is nobody
    /// to have issued a code yet.
    #[serde(default)]
    invite_code: Option<String>,
}

#[derive(Deserialize)]
struct LoginRequest {
    username: String,
    password: String,
    device_name: String,
}

#[derive(Deserialize)]
struct RefreshRequest {
    refresh_token: String,
}

#[derive(Serialize)]
struct TokenResponse {
    user_id: String,
    access_token: String,
    refresh_token: String,
    access_expires_at: i64,
}

#[derive(Serialize)]
struct TicketResponse {
    ticket: String,
    expires_at: i64,
}

fn token_response(tokens: &IssuedTokens) -> TokenResponse {
    TokenResponse {
        user_id: tokens.user_id.to_string(),
        access_token: tokens.access_token.clone(),
        refresh_token: tokens.refresh_token.clone(),
        access_expires_at: tokens.access_expires_at,
    }
}

// --- Handlers ---

/// Creates an account.
///
/// Open only until the deployment is claimed; after that, joining is by
/// invitation, which [`crate::store::Store::register_account`] applies in the
/// same transaction as the account insert. The "no code at all" case is
/// answered before hashing, so the cheapest way to hammer this endpoint does
/// not also buy an Argon2id run per attempt.
///
/// The first account to register also claims an unclaimed deployment, seeding
/// the @everyone and admin roles and a general channel. Without that a fresh
/// server has no roles and no channels, so nobody could do anything.
async fn register(
    _limited: RateLimited<PASSWORD>,
    State(state): State<AppState>,
    Json(req): Json<RegisterRequest>,
) -> Result<Json<TokenResponse>, ApiError> {
    validate_username(&req.username)?;
    validate_password(&req.password)?;
    validate_label(&req.display_name, "display_name must be 1 to 64 characters")?;
    validate_label(&req.device_name, "device_name must be 1 to 64 characters")?;

    let invite_code = req
        .invite_code
        .as_deref()
        .map(str::trim)
        .filter(|c| !c.is_empty());
    // Answered before hashing so a doomed request costs no Argon2id run. The
    // store re-checks both inside its transaction, which is what settles a
    // claim or a policy change racing this.
    if invite_code.is_none()
        && state.store.is_bootstrapped().await?
        && state.store.join_policy().await? == JoinPolicy::Invite
    {
        return Err(ApiError::BadRequest(INVITE_REQUIRED));
    }

    let hash = state.auth.hash_password(req.password).await?;
    let account = match state
        .store
        .register_account(&req.username, &req.display_name, &hash, invite_code)
        .await
    {
        Ok(account) => account,
        Err(RegisterError::UsernameTaken) => {
            return Err(ApiError::Conflict("username is already taken"));
        }
        // The deployment was claimed between the pre-check above and the
        // insert, so this registration needs a code after all.
        Err(RegisterError::InviteRequired) => return Err(ApiError::BadRequest(INVITE_REQUIRED)),
        Err(RegisterError::InviteUnusable) => {
            return Err(ApiError::BadRequest("that invite cannot be used"));
        }
        Err(RegisterError::Internal(err)) => return Err(err.into()),
    };

    // Seeds roles and a general channel on an unclaimed deployment; see the
    // note on this function.
    if let Bootstrap::Claimed = state.store.bootstrap_deployment(account.id).await? {
        tracing::info!(user_id = %account.id, "deployment claimed by its first account");
    }

    let tokens = state
        .store
        .open_session(account.id, &req.device_name)
        .await?;
    Ok(Json(token_response(&tokens)))
}

async fn login(
    _limited: RateLimited<PASSWORD>,
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> Result<Json<TokenResponse>, ApiError> {
    validate_username(&req.username)?;
    validate_password(&req.password)?;
    validate_label(&req.device_name, "device_name must be 1 to 64 characters")?;

    let credentials = state.store.find_credentials(&req.username).await?;
    let verified = match &credentials {
        Some((_, hash)) => {
            state
                .auth
                .verify_password(req.password, hash.clone())
                .await?
        }
        // Spend a comparable amount of time so a missing account is not
        // distinguishable from a wrong password by response latency.
        None => {
            state.auth.verify_decoy().await?;
            false
        }
    };

    let Some((user_id, _)) = credentials else {
        return Err(ApiError::Unauthorized);
    };
    if !verified {
        return Err(ApiError::Unauthorized);
    }

    let tokens = state.store.open_session(user_id, &req.device_name).await?;
    Ok(Json(token_response(&tokens)))
}

async fn refresh(
    _limited: RateLimited<REFRESH>,
    State(state): State<AppState>,
    Json(req): Json<RefreshRequest>,
) -> Result<Json<TokenResponse>, ApiError> {
    match state.store.rotate_refresh(&req.refresh_token).await? {
        RefreshOutcome::Rotated(tokens) => Ok(Json(token_response(&tokens))),
        // A benign miss and a detected replay look identical to the client: the
        // only move either way is to log in again.
        RefreshOutcome::Denied | RefreshOutcome::Reused => Err(ApiError::Unauthorized),
    }
}

async fn ws_ticket(
    Authed(ctx): Authed,
    parts: Parts,
    State(state): State<AppState>,
) -> Result<Json<TicketResponse>, ApiError> {
    enforce(&state, &parts, Some(&ctx), Class::Ticket)?;
    let (ticket, expires_at) = state.store.mint_ws_ticket(&ctx).await?;
    Ok(Json(TicketResponse { ticket, expires_at }))
}

async fn logout(
    AuthedLimited(ctx): AuthedLimited<WRITE>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    state.store.revoke_session(ctx.session_id).await?;
    // Drop any live WebSocket on this session at once, so revocation is instant
    // over the socket too, not just for the next REST call.
    state.hub.publish(Event::SessionRevoked(ctx.session_id));
    Ok(StatusCode::NO_CONTENT)
}

/// Deletes the caller's own account: purge personal data, anonymize authored
/// content, tombstone the user, and revoke every session (closing live sockets).
async fn delete_account(
    AuthedLimited(ctx): AuthedLimited<WRITE>,
    State(state): State<AppState>,
) -> Result<StatusCode, ApiError> {
    let revoked = match state.store.delete_account(ctx.user_id).await {
        Ok(revoked) => revoked,
        // A refusal is the caller's situation, not a server fault, so it must
        // not surface as a 500.
        Err(DeleteAccountError::WouldStrandDeployment) => {
            return Err(ApiError::Conflict(
                "you are the only administrator; appoint another before deleting your account",
            ));
        }
        Err(DeleteAccountError::Internal(e)) => return Err(e.into()),
    };
    for session_id in revoked {
        state.hub.publish(Event::SessionRevoked(session_id));
    }
    if let Err(err) = state.media.delete_avatar(&ctx.user_id.to_string()).await {
        tracing::warn!(error = %err, "failed to delete an account's avatar file");
    }
    Ok(StatusCode::NO_CONTENT)
}

// --- Validation ---

/// `everyone` and `here` are reserved, case-insensitively, so `@everyone` and
/// `@here` (`push::recipients::resolved_mentions`) can never collide with a
/// real account - a plain username-shaped word would otherwise be
/// ambiguous between "the reserved mention" and "the person who registered
/// it first".
const RESERVED_USERNAMES: [&str; 2] = ["everyone", "here"];

fn validate_username(username: &str) -> Result<(), ApiError> {
    let len = username.chars().count();
    if !(1..=32).contains(&len) {
        return Err(ApiError::BadRequest("username must be 1 to 32 characters"));
    }
    let allowed = username
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'));
    if !allowed {
        return Err(ApiError::BadRequest(
            "username may contain only letters, digits, and _ . -",
        ));
    }
    if RESERVED_USERNAMES.contains(&username.to_ascii_lowercase().as_str()) {
        return Err(ApiError::BadRequest(
            "that username is reserved for @everyone/@here mentions",
        ));
    }
    Ok(())
}

/// Cross-checked in this module's own tests against `tests/fixtures/
/// onboarding_error_strings.json`, the fixture the client's onboarding
/// snapshot tests also read, so this exact wording cannot drift from the
/// fixture text a reviewer sees in a screenshot.
const PASSWORD_LENGTH_MESSAGE: &str = "password must be 8 to 1024 characters";

/// Shared with the reset-password consumption endpoint, so a reset cannot be
/// used to set a weaker password than registration would ever allow.
pub(crate) fn validate_password(password: &str) -> Result<(), ApiError> {
    let len = password.chars().count();
    if !(8..=1024).contains(&len) {
        return Err(ApiError::BadRequest(PASSWORD_LENGTH_MESSAGE));
    }
    Ok(())
}

/// Shared with the display-name-only update on `/me`, so a later rename
/// cannot bypass the same anti-spoofing checks registration enforces up
/// front.
pub(crate) fn validate_label(value: &str, message: &'static str) -> Result<(), ApiError> {
    let len = value.chars().count();
    if !(1..=64).contains(&len) {
        return Err(ApiError::BadRequest(message));
    }
    if value.trim().is_empty() {
        return Err(ApiError::BadRequest("name must not be blank"));
    }
    if value.chars().any(is_disallowed_label_char) {
        return Err(ApiError::BadRequest(
            "name must not contain control or text-direction characters",
        ));
    }
    Ok(())
}

/// Rejects control (Cc) characters and the bidi and zero-width format characters
/// used to spoof how a name renders to other members. `pub(crate)`: `http::users`
/// reuses this exact blocklist for a status line's own validation, rather than
/// keeping a second copy of the same spoofing-character set to drift from.
pub(crate) fn is_disallowed_label_char(c: char) -> bool {
    c.is_control()
        || matches!(c,
            '\u{200B}'..='\u{200F}'   // zero-width space and joiners, LRM, RLM
            | '\u{202A}'..='\u{202E}' // bidi embeddings and overrides
            | '\u{2060}'              // word joiner
            | '\u{2066}'..='\u{2069}' // bidi isolates
            | '\u{FEFF}'              // zero-width no-break space / BOM
        )
}

#[cfg(test)]
mod tests {
    /// `everyone`/`here` are refused case-insensitively, and a name that
    /// merely contains one as a substring is untouched - only the reserved
    /// word itself is off limits.
    #[test]
    fn reserved_mention_words_are_refused_as_usernames_case_insensitively() {
        assert!(super::validate_username("everyone").is_err());
        assert!(super::validate_username("Everyone").is_err());
        assert!(super::validate_username("HERE").is_err());
        assert!(super::validate_username("everyone1").is_ok());
        assert!(super::validate_username("not-here").is_ok());
    }

    /// The length rule is inclusive at both ends: empty is refused, one
    /// character is enough, thirty-two is the ceiling, and thirty-three is
    /// over it.
    #[test]
    fn a_username_must_be_one_to_thirty_two_characters() {
        assert!(super::validate_username("").is_err());
        assert!(super::validate_username("a").is_ok());
        assert!(super::validate_username(&"a".repeat(32)).is_ok());
        assert!(super::validate_username(&"a".repeat(33)).is_err());
    }

    /// Only ASCII letters, digits and `_ . -` pass; a space, an `@`, a
    /// non-ASCII letter, and other punctuation are each refused, so a username
    /// can never carry a character a mention or a path would then have to
    /// escape. Length is checked first, so every case here is short enough to
    /// reach the character rule.
    #[test]
    fn a_username_allows_only_letters_digits_and_a_few_marks() {
        assert!(super::validate_username("aZ09_.-").is_ok());
        for bad in [
            "has space",
            "has@at",
            "café",
            "bang!",
            "slash/here",
            "colon:",
        ] {
            assert!(super::validate_username(bad).is_err(), "{bad:?}");
        }
    }

    /// A display label allows the unicode a username cannot - letters of any
    /// script, spaces, emoji - and is bounded 1 to 64 characters. A name that
    /// is only whitespace passes the length check but is refused as blank.
    #[test]
    fn a_display_label_is_bounded_and_may_not_be_only_whitespace() {
        let msg = "label bad";
        assert!(super::validate_label("A", msg).is_ok());
        assert!(super::validate_label("José 日本語 🎉", msg).is_ok());
        assert!(super::validate_label(&"a".repeat(64), msg).is_ok());
        assert!(super::validate_label("", msg).is_err());
        assert!(super::validate_label(&"a".repeat(65), msg).is_err());
        assert!(super::validate_label("   ", msg).is_err());
    }

    /// The one thing a display label cannot carry: control characters, and the
    /// zero-width and bidi-override characters a name would otherwise use to
    /// spoof how it renders (the right-to-left override is the classic one).
    #[test]
    fn a_display_label_refuses_control_and_direction_characters() {
        let msg = "label bad";
        for bad in [
            "a\nb",
            "a\u{202E}b",
            "a\u{200B}b",
            "a\u{FEFF}b",
            "a\u{2066}b",
        ] {
            assert!(super::validate_label(bad, msg).is_err(), "{bad:?}");
        }
    }

    /// The password length rule itself, not only its wording: inclusive 8 to
    /// 1024, counted by character.
    #[test]
    fn a_password_must_be_eight_to_1024_characters() {
        assert!(super::validate_password(&"a".repeat(7)).is_err());
        assert!(super::validate_password(&"a".repeat(8)).is_ok());
        assert!(super::validate_password(&"a".repeat(1024)).is_ok());
        assert!(super::validate_password(&"a".repeat(1025)).is_err());
    }

    /// Cross-checked against the same string in `client/packages/app/test/
    /// support/onboarding_error_strings.dart`, both read from `tests/
    /// fixtures/onboarding_error_strings.json` - editing the length rule's
    /// wording on one side without the other fails whichever side the
    /// fixture no longer matches.
    #[test]
    fn password_length_message_matches_the_shared_onboarding_fixture() {
        let fixture = load_fixture();
        assert_eq!(
            super::PASSWORD_LENGTH_MESSAGE,
            fixture.password_length_error
        );
    }

    #[derive(serde::Deserialize)]
    struct OnboardingErrorStrings {
        password_length_error: String,
    }

    fn load_fixture() -> OnboardingErrorStrings {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/onboarding_error_strings.json");
        let raw = std::fs::read_to_string(&path)
            .unwrap_or_else(|e| panic!("reading {}: {e}", path.display()));
        serde_json::from_str(&raw).expect("onboarding_error_strings.json must be valid JSON")
    }
}
