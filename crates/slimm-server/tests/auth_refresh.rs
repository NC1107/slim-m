// SPDX-License-Identifier: AGPL-3.0-only
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

#[tokio::test]
async fn concurrent_double_refresh_within_grace_denies_softly() {
    // With the default grace window, replaying the just-spent token is treated as the client racing itself, not as theft.
    let (store, _auth, user_id, _guard) = with_alice().await;
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
    let (path, _guard) = support::TestDbGuard::new("slimm-auth-refresh-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
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

/// Two genuinely concurrent refreshes of the same token resolve cleanly: exactly
/// one rotates, the other is a soft deny, neither errors, and the session lives.
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
