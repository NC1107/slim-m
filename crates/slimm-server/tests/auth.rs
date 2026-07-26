// SPDX-License-Identifier: AGPL-3.0-only
//! Integration tests for auth against a real embedded SQLite db, plus one HTTP
//! round-trip proving the wiring end to end.

use std::time::Duration;

use axum::body::Body;
use axum::http::{Request, StatusCode};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::{RefreshOutcome, RegisterError, Store};
use tower::ServiceExt;

async fn store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-auth-test-{}.db", uuid::Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        push_relay_url: None,
        push_relay_key: None,
        livekit_url: None,
        livekit_api_key: None,
        livekit_api_secret: None,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

const PASSWORD: &str = "correct horse battery staple";

/// Registers `alice` with a real Argon2id hash and returns the store, the auth
/// service, and the new user id.
async fn with_alice() -> (Store, Auth, slimm_server::ids::UserId) {
    let store = store().await;
    let auth = Auth::new(2).expect("auth service");
    let hash = auth
        .hash_password(PASSWORD.to_owned())
        .await
        .expect("hash password");
    let account = store
        .create_account("alice", "Alice", &hash)
        .await
        .expect("register alice");
    (store, auth, account.id)
}

#[tokio::test]
async fn access_token_resolves_to_its_session() {
    let (store, _auth, user_id) = with_alice().await;
    let tokens = store.open_session(user_id, "laptop").await.unwrap();

    let ctx = store
        .authenticate(&tokens.access_token)
        .await
        .unwrap()
        .expect("a fresh access token resolves");
    assert_eq!(ctx.user_id, user_id);
    assert_eq!(ctx.session_id, tokens.session_id);
    assert_eq!(ctx.device_id, tokens.device_id);

    // A garbage token resolves to nothing.
    assert!(
        store
            .authenticate("not-a-real-token")
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn password_verification_and_username_uniqueness() {
    let (store, auth, user_id) = with_alice().await;

    let (found_id, hash) = store
        .find_credentials("alice")
        .await
        .unwrap()
        .expect("alice exists");
    assert_eq!(found_id, user_id);
    assert!(
        auth.verify_password(PASSWORD.to_owned(), hash.clone())
            .await
            .unwrap()
    );
    assert!(
        !auth
            .verify_password("wrong".to_owned(), hash)
            .await
            .unwrap()
    );

    // Unknown user: no credentials.
    assert!(store.find_credentials("nobody").await.unwrap().is_none());

    // The live username is taken.
    let dup = store.create_account("alice", "Alice Two", "x").await;
    assert!(matches!(dup, Err(RegisterError::UsernameTaken)));
}

#[tokio::test]
async fn refresh_rotates_and_drops_the_old_access_token() {
    let (store, _auth, user_id) = with_alice().await;
    let original = store.open_session(user_id, "laptop").await.unwrap();

    let rotated = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        _ => panic!("first refresh should rotate"),
    };
    assert_ne!(rotated.refresh_token, original.refresh_token);
    // The new access token works; the old one was dropped in the same step.
    assert!(
        store
            .authenticate(&rotated.access_token)
            .await
            .unwrap()
            .is_some()
    );
    assert!(
        store
            .authenticate(&original.access_token)
            .await
            .unwrap()
            .is_none()
    );
    // The new refresh token rotates again.
    assert!(matches!(
        store.rotate_refresh(&rotated.refresh_token).await.unwrap(),
        RefreshOutcome::Rotated(_)
    ));
}

#[tokio::test]
async fn concurrent_double_refresh_within_grace_denies_softly() {
    // With the default grace window, replaying the just-spent token immediately
    // is treated as the client racing itself, not as theft.
    let (store, _auth, user_id) = with_alice().await;
    let original = store.open_session(user_id, "laptop").await.unwrap();

    let rotated = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        _ => panic!("first refresh should rotate"),
    };

    // Immediate replay of the spent original is denied, but not reuse.
    assert!(matches!(
        store.rotate_refresh(&original.refresh_token).await.unwrap(),
        RefreshOutcome::Denied
    ));
    // The winning rotation's tokens still work: the session was not revoked.
    assert!(
        store
            .authenticate(&rotated.access_token)
            .await
            .unwrap()
            .is_some()
    );
    assert!(matches!(
        store.rotate_refresh(&rotated.refresh_token).await.unwrap(),
        RefreshOutcome::Rotated(_)
    ));
}

#[tokio::test]
async fn stale_refresh_reuse_revokes_the_family() {
    // A zero grace window makes any replay of a spent token count as reuse.
    let path = std::env::temp_dir()
        .join(format!("slimm-auth-test-{}.db", uuid::Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        push_relay_url: None,
        push_relay_key: None,
        livekit_url: None,
        livekit_api_key: None,
        livekit_api_secret: None,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    let store = Store::with_reuse_grace_ms(pool, 0);
    let auth = Auth::new(2).expect("auth service");
    let hash = auth.hash_password(PASSWORD.to_owned()).await.expect("hash");
    let account = store
        .create_account("alice", "Alice", &hash)
        .await
        .expect("register");

    let original = store.open_session(account.id, "laptop").await.unwrap();
    let rotated = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        _ => panic!("first refresh should rotate"),
    };

    // Let a moment pass so the replay lands outside the (zero) grace window.
    tokio::time::sleep(Duration::from_millis(20)).await;

    // Replaying the spent original is now genuine reuse: the family is revoked.
    assert!(matches!(
        store.rotate_refresh(&original.refresh_token).await.unwrap(),
        RefreshOutcome::Reused
    ));
    // The whole family is dead: the good rotated token is denied and its access
    // token no longer authenticates.
    assert!(matches!(
        store.rotate_refresh(&rotated.refresh_token).await.unwrap(),
        RefreshOutcome::Denied
    ));
    assert!(
        store
            .authenticate(&rotated.access_token)
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn revoke_session_is_instant() {
    let (store, _auth, user_id) = with_alice().await;
    let tokens = store.open_session(user_id, "phone").await.unwrap();
    assert!(
        store
            .authenticate(&tokens.access_token)
            .await
            .unwrap()
            .is_some()
    );

    store.revoke_session(tokens.session_id).await.unwrap();

    // The bearer token stops resolving immediately, and refresh is denied.
    assert!(
        store
            .authenticate(&tokens.access_token)
            .await
            .unwrap()
            .is_none()
    );
    assert!(matches!(
        store.rotate_refresh(&tokens.refresh_token).await.unwrap(),
        RefreshOutcome::Denied
    ));
}

#[tokio::test]
async fn revoke_device_kills_its_sessions() {
    let (store, _auth, user_id) = with_alice().await;
    let tokens = store.open_session(user_id, "desktop").await.unwrap();

    store.revoke_device(tokens.device_id).await.unwrap();
    assert!(
        store
            .authenticate(&tokens.access_token)
            .await
            .unwrap()
            .is_none()
    );
}

#[tokio::test]
async fn ws_ticket_is_single_use_and_session_bound() {
    let (store, _auth, user_id) = with_alice().await;
    let tokens = store.open_session(user_id, "tablet").await.unwrap();
    let ctx = store
        .authenticate(&tokens.access_token)
        .await
        .unwrap()
        .unwrap();

    let (ticket, _expires_at) = store.mint_ws_ticket(&ctx).await.unwrap();
    let redeemed = store
        .redeem_ws_ticket(&ticket)
        .await
        .unwrap()
        .expect("first redemption resolves the session");
    assert_eq!(redeemed, ctx);

    // Single-use: a second redemption fails, as does an unknown ticket.
    assert!(store.redeem_ws_ticket(&ticket).await.unwrap().is_none());
    assert!(
        store
            .redeem_ws_ticket("bogus-ticket")
            .await
            .unwrap()
            .is_none()
    );

    // A ticket dies with its session.
    let (ticket, _) = store.mint_ws_ticket(&ctx).await.unwrap();
    store.revoke_session(ctx.session_id).await.unwrap();
    assert!(store.redeem_ws_ticket(&ticket).await.unwrap().is_none());
}

/// End to end over HTTP: register, mint a connect ticket with the bearer token,
/// log out, and confirm the same token is then rejected.
#[tokio::test]
async fn http_register_ticket_and_logout() {
    let store = store().await;
    let auth = Auth::new(2).expect("auth service");
    let app = http::router(AppState {
        store,
        auth,
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
    });

    // Register.
    let body = serde_json::json!({
        "username": "bob",
        "display_name": "Bob",
        "password": "hunter2hunter2",
        "device_name": "cli"
    })
    .to_string();
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(body))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let json: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    let access = json["access_token"].as_str().unwrap().to_owned();

    // A connect ticket requires the bearer token and succeeds.
    let ticket = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/ws-ticket")
                .header("authorization", format!("Bearer {access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(ticket.status(), StatusCode::OK);

    // Log out.
    let logout = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/logout")
                .header("authorization", format!("Bearer {access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(logout.status(), StatusCode::NO_CONTENT);

    // The same token is now rejected.
    let after = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/ws-ticket")
                .header("authorization", format!("Bearer {access}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(after.status(), StatusCode::UNAUTHORIZED);
}

/// Wrong password and unknown user are both a plain 401.
#[tokio::test]
async fn http_login_rejects_bad_credentials() {
    let (store, auth, _user_id) = with_alice().await;
    let app = http::router(AppState {
        store,
        auth,
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
    });

    let wrong_password = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "username": "alice",
                        "password": "the wrong password",
                        "device_name": "cli"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(wrong_password.status(), StatusCode::UNAUTHORIZED);

    let unknown_user = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "username": "ghost",
                        "password": "does not matter",
                        "device_name": "cli"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(unknown_user.status(), StatusCode::UNAUTHORIZED);
}

/// Two genuinely concurrent refreshes of the same token resolve cleanly: exactly
/// one rotates, the other is a soft deny, neither errors, and the session lives.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn concurrent_refresh_of_same_token_never_errors() {
    let (store, _auth, user_id) = with_alice().await;
    let original = store.open_session(user_id, "laptop").await.unwrap();
    let token = original.refresh_token.clone();

    let (s1, s2) = (store.clone(), store.clone());
    let (t1, t2) = (token.clone(), token.clone());
    let h1 = tokio::spawn(async move { s1.rotate_refresh(&t1).await });
    let h2 = tokio::spawn(async move { s2.rotate_refresh(&t2).await });
    let o1 = h1.await.unwrap().expect("no database error");
    let o2 = h2.await.unwrap().expect("no database error");

    let mut rotated = None;
    let mut denied = 0;
    for outcome in [o1, o2] {
        match outcome {
            RefreshOutcome::Rotated(tokens) => {
                assert!(rotated.is_none(), "only one rotation may win");
                rotated = Some(tokens);
            }
            RefreshOutcome::Denied => denied += 1,
            RefreshOutcome::Reused => panic!("a benign concurrent race must not read as reuse"),
        }
    }
    assert_eq!(denied, 1, "the loser is denied softly");

    // The session survived the race: the winner's access token still works.
    let winner = rotated.expect("one rotation won");
    assert!(
        store
            .authenticate(&winner.access_token)
            .await
            .unwrap()
            .is_some()
    );
}

/// A display name carrying a bidi-override character is rejected at registration.
#[tokio::test]
async fn http_register_rejects_spoofing_display_name() {
    let store = store().await;
    let auth = Auth::new(2).expect("auth service");
    let app = http::router(AppState {
        store,
        auth,
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
    });

    let response = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "username": "mallory",
                        "display_name": "\u{202E}nimda",
                        "password": "hunter2hunter2",
                        "device_name": "cli"
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}

/// A connect ticket is single use. The redemption is a claim-first conditional
/// UPDATE for exactly this reason, but every other test here spends one
/// sequentially, which cannot tell an atomic claim from a check-then-write that
/// happens to work when nothing races it.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_redemptions_of_one_ticket_admit_exactly_one() {
    let (store, _auth, user_id) = with_alice().await;
    let tokens = store.open_session(user_id, "laptop").await.unwrap();
    let ctx = store
        .authenticate(&tokens.access_token)
        .await
        .unwrap()
        .expect("the fresh access token authenticates");
    let (ticket, _expires_at) = store.mint_ws_ticket(&ctx).await.unwrap();

    let racers = (0..8).map(|_| {
        let store = store.clone();
        let ticket = ticket.clone();
        tokio::spawn(async move { store.redeem_ws_ticket(&ticket).await })
    });
    let outcomes = futures_util::future::join_all(racers).await;

    let mut admitted = 0;
    for outcome in outcomes {
        let redeemed = outcome
            .expect("redemption task panicked")
            .expect("a racing redemption must not error");
        if redeemed.is_some() {
            admitted += 1;
        }
    }
    assert_eq!(
        admitted, 1,
        "exactly one racer may spend a single-use ticket, however many present it at once"
    );
}
