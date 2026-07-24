// SPDX-License-Identifier: AGPL-3.0-only
//! Integration tests for the message store against a real embedded SQLite db.

use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::ids::{MessageId, Seq};
use slimm_server::store::Store;

async fn store() -> Store {
    let path = format!("/tmp/slimm-test-{}.db", uuid::Uuid::now_v7());
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

#[tokio::test]
async fn seq_is_monotonic_and_independent_per_channel() {
    let s = store().await;
    let author = s.create_user("mara", "Mara").await.unwrap();
    let a = s.create_channel("general", "text").await.unwrap();
    let b = s.create_channel("gaming", "text").await.unwrap();

    let a1 = s
        .send_message(a.id, author.id, MessageId::generate(), "one")
        .await
        .unwrap();
    let a2 = s
        .send_message(a.id, author.id, MessageId::generate(), "two")
        .await
        .unwrap();
    let b1 = s
        .send_message(b.id, author.id, MessageId::generate(), "other")
        .await
        .unwrap();

    assert_eq!(a1.seq, Seq(1));
    assert_eq!(a2.seq, Seq(2));
    // A separate channel has its own counter, so this is 1, not 3.
    assert_eq!(b1.seq, Seq(1));
}

#[tokio::test]
async fn send_is_idempotent_by_id() {
    let s = store().await;
    let author = s.create_user("theo", "Theo").await.unwrap();
    let c = s.create_channel("general", "text").await.unwrap();

    let id = MessageId::generate();
    let first = s.send_message(c.id, author.id, id, "hi").await.unwrap();
    // A retry with the same id returns the stored message and wastes no sequence.
    let retry = s
        .send_message(c.id, author.id, id, "hi again")
        .await
        .unwrap();

    assert_eq!(first.seq, retry.seq);
    assert_eq!(first.id, retry.id);
    assert_eq!(
        retry.content, "hi",
        "returns the stored message, not the retry body"
    );

    // The next real send is seq 2, proving the retry did not consume seq 2.
    let second = s
        .send_message(c.id, author.id, MessageId::generate(), "second")
        .await
        .unwrap();
    assert_eq!(second.seq, Seq(2));

    let all = s.list_messages(c.id, None, 100).await.unwrap();
    assert_eq!(all.len(), 2, "the retry did not create a duplicate row");
}

#[tokio::test]
async fn edit_and_keyset_pagination() {
    let s = store().await;
    let author = s.create_user("priya", "Priya").await.unwrap();
    let c = s.create_channel("general", "text").await.unwrap();
    for i in 0..5 {
        s.send_message(c.id, author.id, MessageId::generate(), &format!("m{i}"))
            .await
            .unwrap();
    }

    // Newest-first page of 3.
    let page = s.list_messages(c.id, None, 3).await.unwrap();
    assert_eq!(page.len(), 3);
    assert_eq!(page[0].seq, Seq(5));
    assert_eq!(page[2].seq, Seq(3));

    // Page backwards from the smallest seq seen.
    let next = s.list_messages(c.id, Some(page[2].seq.0), 3).await.unwrap();
    assert_eq!(next.len(), 2);
    assert_eq!(next[0].seq, Seq(2));
    assert_eq!(next[1].seq, Seq(1));

    // Edit stamps edited_at and changes the content.
    let edited = s.edit_message(page[0].id, "edited").await.unwrap().unwrap();
    assert_eq!(edited.content, "edited");
    assert!(edited.edited_at.is_some());

    // Editing something that does not exist is a clean None.
    assert!(
        s.edit_message(MessageId::generate(), "x")
            .await
            .unwrap()
            .is_none()
    );
}
