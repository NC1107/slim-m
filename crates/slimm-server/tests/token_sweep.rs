// SPDX-License-Identifier: AGPL-3.0-only
//! The expired-token sweep.
//!
//! Every sign-in writes an access token and a refresh token, every rotation
//! writes another refresh token, and every socket connect writes a ticket.
//! Nothing deleted any of them outside the targeted revocation paths, so all
//! three tables grew for the life of a deployment.
//!
//! The delicate part is what the sweep must NOT remove. Reuse detection works
//! by finding a spent refresh row and seeing `used_at` set; delete that row too
//! eagerly and a replayed token becomes indistinguishable from one that never
//! existed, so a leaked family is denied softly instead of being revoked.

use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::store::{RefreshOutcome, Store};
use sqlx::SqlitePool;

mod support;

async fn pool() -> (SqlitePool, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-sweep-test");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    (
        db::connect(&config).await.expect("connect + migrate"),
        guard,
    )
}

/// Drags a table's `expires_at` back by `age_ms`, standing in for rows written
/// that long ago without making the test wait.
async fn age_rows(pool: &SqlitePool, table: &str, age_ms: i64) {
    let sql = format!("UPDATE {table} SET expires_at = expires_at - ?");
    sqlx::query(&sql)
        .bind(age_ms)
        .execute(pool)
        .await
        .expect("age rows");
}

async fn count(pool: &SqlitePool, table: &str) -> i64 {
    let sql = format!("SELECT COUNT(*) FROM {table}");
    sqlx::query_scalar(&sql)
        .fetch_one(pool)
        .await
        .expect("count rows")
}

const DAY_MS: i64 = 24 * 60 * 60 * 1000;

#[tokio::test]
async fn a_fresh_deployment_has_nothing_to_sweep() {
    let (pool, _guard) = pool().await;
    let store = Store::new(pool.clone());
    let user = store.create_user("alice", "Alice").await.unwrap();
    let tokens = store.open_session(user.id, "laptop").await.unwrap();
    let ctx = store
        .authenticate(&tokens.access_token)
        .await
        .unwrap()
        .unwrap();
    store.mint_ws_ticket(&ctx).await.unwrap();

    let swept = store.sweep_expired_tokens().await.unwrap();
    assert_eq!(
        swept.total(),
        0,
        "nothing has expired yet, so a sweep must not touch a live session"
    );
    assert_eq!(count(&pool, "access_tokens").await, 1);
    assert_eq!(count(&pool, "refresh_tokens").await, 1);
    assert_eq!(count(&pool, "ws_tickets").await, 1);
}

#[tokio::test]
async fn long_dead_rows_are_removed_from_all_three_tables() {
    let (pool, _guard) = pool().await;
    let store = Store::new(pool.clone());
    let user = store.create_user("alice", "Alice").await.unwrap();
    let tokens = store.open_session(user.id, "laptop").await.unwrap();
    let ctx = store
        .authenticate(&tokens.access_token)
        .await
        .unwrap()
        .unwrap();
    store.mint_ws_ticket(&ctx).await.unwrap();

    // Well past every grace window: refresh keeps rows a further 30 days after
    // their own 30-day expiry, which is the longest of the three.
    age_rows(&pool, "access_tokens", 120 * DAY_MS).await;
    age_rows(&pool, "refresh_tokens", 120 * DAY_MS).await;
    age_rows(&pool, "ws_tickets", 120 * DAY_MS).await;

    let swept = store.sweep_expired_tokens().await.unwrap();
    assert_eq!(swept.access_tokens, 1);
    assert_eq!(swept.refresh_tokens, 1);
    assert_eq!(swept.ws_tickets, 1);
    assert_eq!(count(&pool, "access_tokens").await, 0);
    assert_eq!(count(&pool, "refresh_tokens").await, 0);
    assert_eq!(count(&pool, "ws_tickets").await, 0);
}

/// The whole point of the grace window. A refresh token that expired recently
/// is exactly the one an attacker would replay, and detecting that replay needs
/// the row to still be there.
#[tokio::test]
async fn a_spent_refresh_token_survives_long_enough_to_still_catch_reuse() {
    let (pool, _guard) = pool().await;
    let store = Store::with_reuse_grace_ms(pool.clone(), 0);
    let user = store.create_user("alice", "Alice").await.unwrap();
    let original = store.open_session(user.id, "laptop").await.unwrap();
    match store.rotate_refresh(&original.refresh_token).await.unwrap() {
        RefreshOutcome::Rotated(_) => {}
        _ => panic!("first rotation should succeed"),
    }

    // Past its own 30-day expiry, but inside the sweep's grace.
    age_rows(&pool, "refresh_tokens", 31 * DAY_MS).await;
    let swept = store.sweep_expired_tokens().await.unwrap();
    assert_eq!(
        swept.refresh_tokens, 0,
        "a token only just past expiry is still the evidence reuse detection reads"
    );

    // The grace window is zero, but `now - used_at` is whole milliseconds and
    // landing inside the same one reads as an honest client, not a replay.
    tokio::time::sleep(std::time::Duration::from_millis(20)).await;

    assert!(
        matches!(
            store.rotate_refresh(&original.refresh_token).await.unwrap(),
            RefreshOutcome::Reused
        ),
        "replaying the spent token must still be detected as reuse, not merely denied"
    );
}

#[tokio::test]
async fn sweeping_does_not_disturb_a_live_session_alongside_dead_rows() {
    let (pool, _guard) = pool().await;
    let store = Store::new(pool.clone());
    let user = store.create_user("alice", "Alice").await.unwrap();

    let stale = store.open_session(user.id, "old-laptop").await.unwrap();
    age_rows(&pool, "access_tokens", 120 * DAY_MS).await;
    age_rows(&pool, "refresh_tokens", 120 * DAY_MS).await;

    // A second session opened after the ageing, so its rows are current.
    let live = store.open_session(user.id, "phone").await.unwrap();

    let swept = store.sweep_expired_tokens().await.unwrap();
    assert_eq!(swept.access_tokens, 1);
    assert_eq!(swept.refresh_tokens, 1);

    assert!(
        store
            .authenticate(&live.access_token)
            .await
            .unwrap()
            .is_some(),
        "the live session must still authenticate after a sweep"
    );
    assert!(
        store
            .authenticate(&stale.access_token)
            .await
            .unwrap()
            .is_none(),
        "and the swept one must not"
    );
}
