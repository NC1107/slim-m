// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Integration tests for refresh-token rotation: a normal rotation, two
//! genuinely concurrent races over the same token, and reuse of an
//! already-spent token revoking the whole session family.
//!
//! Split out of `auth.rs`, which crossed its 500-line hard budget; the rest
//! of the auth surface (registration, sessions, device removal, ws tickets,
//! and the HTTP round trips) stays there.

use std::time::Duration;

use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::store::{RefreshOutcome, Store};

mod support;

async fn store() -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-auth-refresh-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool), guard)
}

const PASSWORD: &str = "correct horse battery staple";

/// Names an outcome for a panic message; `RefreshOutcome` holds secrets and so
/// is deliberately not `Debug`.
fn outcome_name(outcome: &RefreshOutcome) -> &'static str {
    match outcome {
        RefreshOutcome::Rotated(_) => "Rotated",
        RefreshOutcome::Denied => "Denied",
        RefreshOutcome::Reused => "Reused",
    }
}

/// Registers `alice` with a real Argon2id hash and returns the store, the auth
/// service, the new user id, and the store's db-cleanup guard.
async fn with_alice() -> (Store, Auth, slimm_server::ids::UserId, support::TestDbGuard) {
    let (store, guard) = store().await;
    let auth = Auth::new(2).expect("auth service");
    let hash = auth
        .hash_password(PASSWORD.to_owned())
        .await
        .expect("hash password");
    let account = store
        .create_account("alice", "Alice", &hash)
        .await
        .expect("register alice");
    (store, auth, account.id, guard)
}

#[tokio::test]
async fn refresh_rotates_and_drops_the_old_access_token() {
    let (store, _auth, user_id, _guard) = with_alice().await;
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

/// The bug this file's rotation model exists to prevent: a rotation commits
/// server-side before its response reaches the client, so a dropped response
/// left the client holding a token the server had already spent. Retrying with
/// it used to be a replay, and signed the user out.
///
/// Reproduced by rotating and then throwing the result away, which is exactly
/// what the client sees when the response is lost or the server restarts
/// mid-request.
#[tokio::test]
async fn a_rotation_whose_response_was_lost_lets_the_client_retry() {
    let (store, _auth, user_id, _guard) = with_alice().await;
    let original = store.open_session(user_id, "laptop").await.unwrap();

    // The rotation happens; the client never receives it.
    let lost = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        _ => panic!("first refresh should rotate"),
    };
    drop(lost);

    // The client still holds the original, and it still works.
    let recovered = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        other => panic!(
            "an unconfirmed rotation must not strand the client: {}",
            outcome_name(&other)
        ),
    };
    assert!(
        store
            .authenticate(&recovered.access_token)
            .await
            .unwrap()
            .is_some(),
        "the recovered pair signs the same session back in, with no fresh login"
    );
}

/// Recovery is not unbounded: once the client proves it received a replacement,
/// the token that rotation spent is retired and replaying it is reuse again.
#[tokio::test]
async fn confirming_a_rotation_retires_the_token_it_spent() {
    let (store, _auth, user_id, _guard) = with_alice().await;
    let original = store.open_session(user_id, "laptop").await.unwrap();

    let rotated = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        _ => panic!("first refresh should rotate"),
    };
    // Using the new access token is the confirmation.
    assert!(
        store
            .authenticate(&rotated.access_token)
            .await
            .unwrap()
            .is_some()
    );

    assert!(
        matches!(
            store.rotate_refresh(&original.refresh_token).await.unwrap(),
            RefreshOutcome::Reused
        ),
        "a confirmed rotation closes the window its predecessor had"
    );
}

#[tokio::test]
async fn stale_refresh_reuse_revokes_the_family() {
    let (store, _auth, user_id, _guard) = with_alice().await;
    let original = store.open_session(user_id, "laptop").await.unwrap();
    let rotated = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        _ => panic!("first refresh should rotate"),
    };
    // Confirmed, so the original is retired and a copy of it is a leak.
    assert!(
        store
            .authenticate(&rotated.access_token)
            .await
            .unwrap()
            .is_some()
    );

    assert!(matches!(
        store.rotate_refresh(&original.refresh_token).await.unwrap(),
        RefreshOutcome::Reused
    ));
    // The whole family is dead: the good rotated token is denied and no longer authenticates.
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

/// Two genuinely concurrent refreshes of the same token resolve cleanly: both
/// rotate, neither errors, and the session lives. Under confirm-before-retire
/// the loser is no longer denied - it presents a token that is spent but not
/// yet retired, which is indistinguishable from an honest retry and is
/// answered as one.
///
/// The property that matters is that the client is never stranded, whichever
/// response it kept. Only the last rotation's access token survives, because
/// rotation still drops the session's prior one - so the earlier pair's access
/// token is dead on arrival. That pair's *refresh* token is still good, which
/// is what makes the difference an extra round trip rather than a sign-out.
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn concurrent_refresh_of_same_token_never_errors() {
    let (store, _auth, user_id, _guard) = with_alice().await;
    let original = store.open_session(user_id, "laptop").await.unwrap();
    let token = original.refresh_token.clone();

    let (s1, s2) = (store.clone(), store.clone());
    let (t1, t2) = (token.clone(), token.clone());
    let h1 = tokio::spawn(async move { s1.rotate_refresh(&t1).await });
    let h2 = tokio::spawn(async move { s2.rotate_refresh(&t2).await });
    let o1 = h1.await.unwrap().expect("no database error");
    let o2 = h2.await.unwrap().expect("no database error");

    let mut issued = Vec::new();
    for outcome in [o1, o2] {
        match outcome {
            RefreshOutcome::Rotated(tokens) => issued.push(tokens),
            other => panic!(
                "a benign concurrent race must not reject either caller: {}",
                outcome_name(&other)
            ),
        }
    }
    assert_eq!(issued.len(), 2);

    // Either pair can be the one the client kept, so neither may strand it.
    for tokens in &issued {
        let live = store
            .authenticate(&tokens.access_token)
            .await
            .unwrap()
            .is_some();
        if live {
            continue;
        }
        assert!(
            matches!(
                store.rotate_refresh(&tokens.refresh_token).await.unwrap(),
                RefreshOutcome::Rotated(_)
            ),
            "a superseded pair must still refresh its way back to a session"
        );
    }
}

/// Reuse detection no longer rides on elapsed time, so this pins the property
/// that replaced the old window: what makes a replay reuse is that the rotation
/// was confirmed, not how long ago it happened. The replay here lands
/// immediately, which under a duration-based window would have been forgiven.
#[tokio::test]
async fn a_replay_after_confirmation_is_reuse_however_soon_it_lands() {
    let (store, _auth, user_id, _guard) = with_alice().await;
    let original = store.open_session(user_id, "laptop").await.unwrap();

    let rotated = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        _ => panic!("first refresh should rotate"),
    };
    store
        .authenticate(&rotated.access_token)
        .await
        .unwrap()
        .expect("confirmation");

    assert!(
        matches!(
            store.rotate_refresh(&original.refresh_token).await.unwrap(),
            RefreshOutcome::Reused
        ),
        "confirmed is confirmed, however few milliseconds ago it happened"
    );
}

/// A rotation issues a pair that expires a TTL from now, the same distance the
/// sign-in pair did; a slip in that arithmetic would hand out tokens with an
/// absurd expiry that nothing else checks.
#[tokio::test]
async fn a_rotation_issues_tokens_with_the_same_lifetime_as_sign_in() {
    let (store, _auth, user_id, _guard) = with_alice().await;
    let original = store.open_session(user_id, "laptop").await.unwrap();
    let rotated = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        _ => panic!("first refresh should rotate"),
    };

    let slack = Duration::from_secs(5).as_millis() as i64;
    assert!(
        (rotated.access_expires_at - original.access_expires_at).abs() < slack,
        "access expiry drifted: {} vs {}",
        rotated.access_expires_at,
        original.access_expires_at
    );
    assert!(
        (rotated.refresh_expires_at - original.refresh_expires_at).abs() < slack,
        "refresh expiry drifted: {} vs {}",
        rotated.refresh_expires_at,
        original.refresh_expires_at
    );
    assert!(rotated.access_expires_at < rotated.refresh_expires_at);
}

/// Confirm-before-retire would have been far simpler if a replay could be
/// handed back the pair its rotation issued, and that is exactly what this
/// design refuses to make possible: tokens are stored only as hashes, so the
/// plaintext cannot be reproduced even by the server that issued it.
#[tokio::test]
async fn rotation_stores_no_plaintext_token() {
    let (path, _guard) = support::TestDbGuard::new("slimm-auth-refresh-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    let store = Store::new(pool.clone());
    let user = store.create_user("alice", "Alice").await.unwrap();

    let original = store.open_session(user.id, "laptop").await.unwrap();
    let rotated = match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(tokens) => tokens,
        _ => panic!("first refresh should rotate"),
    };

    let stored: Vec<String> = sqlx::query_scalar(
        "SELECT token_hash FROM refresh_tokens
         UNION ALL SELECT token_hash FROM access_tokens
         UNION ALL SELECT COALESCE(confirms_refresh_hash, '') FROM access_tokens",
    )
    .fetch_all(&pool)
    .await
    .unwrap();

    for secret in [
        &original.refresh_token,
        &original.access_token,
        &rotated.refresh_token,
        &rotated.access_token,
    ] {
        assert!(
            !stored.iter().any(|value| value == secret),
            "a token's plaintext must never reach the database"
        );
    }
}
