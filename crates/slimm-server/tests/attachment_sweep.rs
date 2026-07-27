// SPDX-License-Identifier: AGPL-3.0-only
//! The orphaned-attachment sweep, and the custom emoji that sits in front of
//! it.
//!
//! An emoji's image is an `attachments` row nothing ever attached to a
//! message, which is exactly the shape the sweep hunts, and
//! `0016_custom_emoji.sql` guards it with `ON DELETE RESTRICT`. RESTRICT is
//! not a filter: it aborts the whole `DELETE`, so a single emoji stopped the
//! sweep for the entire deployment and no orphan was ever reclaimed again.
//! The sweep has to exclude an emoji's bytes itself.

use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::ids::EmojiId;
use slimm_server::store::Store;
use sqlx::SqlitePool;
use uuid::Uuid;

const DAY_MS: i64 = 24 * 60 * 60 * 1000;

async fn pool() -> SqlitePool {
    let path = std::env::temp_dir()
        .join(format!("slimm-attachment-sweep-{}.db", Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    db::connect(&config).await.expect("connect + migrate")
}

/// Drags every attachment's `created_at` back past the sweep's grace window,
/// standing in for an upload made that long ago without making the test wait.
async fn age_attachments(pool: &SqlitePool) {
    sqlx::query("UPDATE attachments SET created_at = created_at - ?")
        .bind(2 * DAY_MS)
        .execute(pool)
        .await
        .expect("age attachments");
}

async fn attachment_count(pool: &SqlitePool) -> i64 {
    sqlx::query_scalar("SELECT COUNT(*) FROM attachments")
        .fetch_one(pool)
        .await
        .expect("count attachments")
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Control: with no emoji anywhere, one aged upload nobody attached is
/// reclaimed. This is the behaviour the emoji case must not change.
#[tokio::test]
async fn an_aged_unattached_upload_is_swept() {
    let pool = pool().await;
    let store = Store::new(pool.clone());

    let orphan = [0xAAu8; 32];
    store
        .store_attachment(&orphan, 8, "image/png", "orphan.png")
        .await
        .unwrap();
    age_attachments(&pool).await;

    let freed = store.sweep_orphaned_attachments().await.unwrap();
    assert_eq!(freed, vec![hex(&orphan)]);
    assert_eq!(attachment_count(&pool).await, 0);
}

/// The regression. A deployment holding one custom emoji must still reclaim a
/// genuine orphan, and must keep the emoji's bytes while doing it.
///
/// Before the fix the emoji's row was itself a delete candidate, RESTRICT
/// aborted the statement, and `sweep_orphaned_attachments` returned an error
/// with the orphan still on disk: attachment garbage collection stopped for
/// the life of the deployment.
#[tokio::test]
async fn an_emoji_does_not_stop_the_sweep_and_its_bytes_survive() {
    let pool = pool().await;
    let store = Store::new(pool.clone());

    let emoji_bytes = [0x11u8; 32];
    let orphan = [0x22u8; 32];
    store
        .store_attachment(&emoji_bytes, 8, "image/png", "party.png")
        .await
        .unwrap();
    store
        .store_attachment(&orphan, 8, "image/png", "orphan.png")
        .await
        .unwrap();
    store
        .create_custom_emoji(EmojiId::generate(), "party", &emoji_bytes, None)
        .await
        .unwrap()
        .expect("the emoji is created");
    age_attachments(&pool).await;

    let freed = store
        .sweep_orphaned_attachments()
        .await
        .expect("an emoji must not fail the sweep");
    assert_eq!(
        freed,
        vec![hex(&orphan)],
        "the genuine orphan is reclaimed and the emoji's bytes are not"
    );

    let kept: Option<Vec<u8>> = sqlx::query_scalar("SELECT sha256 FROM attachments")
        .fetch_optional(&pool)
        .await
        .unwrap();
    assert_eq!(
        kept.as_deref(),
        Some(emoji_bytes.as_slice()),
        "the emoji's row is the only attachment left"
    );

    // The emoji itself still resolves, so the RESTRICT it relies on was never
    // reached rather than merely tolerated.
    let listed = store.list_custom_emoji().await.unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0].sha256, hex(&emoji_bytes));
}

/// Deleting the emoji makes its bytes an ordinary orphan again, so the space
/// is genuinely reclaimable rather than pinned forever by the exclusion.
#[tokio::test]
async fn removing_the_emoji_releases_its_bytes_to_the_next_sweep() {
    let pool = pool().await;
    let store = Store::new(pool.clone());

    let emoji_bytes = [0x33u8; 32];
    store
        .store_attachment(&emoji_bytes, 8, "image/png", "party.png")
        .await
        .unwrap();
    let id = EmojiId::generate();
    store
        .create_custom_emoji(id, "party", &emoji_bytes, None)
        .await
        .unwrap()
        .expect("the emoji is created");
    age_attachments(&pool).await;

    assert!(store.sweep_orphaned_attachments().await.unwrap().is_empty());
    assert!(store.delete_custom_emoji(id).await.unwrap());

    let freed = store.sweep_orphaned_attachments().await.unwrap();
    assert_eq!(freed, vec![hex(&emoji_bytes)]);
    assert_eq!(attachment_count(&pool).await, 0);
}
