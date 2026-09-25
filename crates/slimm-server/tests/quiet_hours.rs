// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The legacy quiet-hours window (migration 0056): `store::quiet_hours` and
//! `store::set_quiet_hours` still read and write `users.quiet_hours_*`
//! exactly as before, so an old client's `/push/quiet-hours` calls keep
//! working - see `http/quiet_hours.rs`'s own doc comment.
//!
//! What moved is enforcement: migration 0081 seeded every existing
//! quiet-hours user into the new notification schedule, and
//! `push::recipients` now reads that schedule, not these columns, when
//! deciding whether to narrow a push. `notification_schedule.rs` and
//! `notification_schedule_migration.rs` are where that behaviour - including
//! the exact case this file used to test, an in-window `everything`
//! recipient narrowed to `mentions` - is covered now. Writing through these
//! two methods alone changes nothing about a live account's push, which is
//! exactly the round trip left to test here.

use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::ids::UserId;
use slimm_server::notifications::QuietHours;
use slimm_server::store::Store;

mod support;

async fn new_store(name: &str) -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new(name);
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool), guard)
}

async fn account(store: &Store, username: &str) -> UserId {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    account.id
}

/// A fresh account has no quiet hours, the same "nothing set yet" default
/// every other notification setting keeps on upgrade.
#[tokio::test]
async fn a_fresh_account_has_no_quiet_hours() {
    let (store, _guard) = new_store("slimm-quiet-hours-default").await;
    let bob = account(&store, "bob").await;
    assert_eq!(store.quiet_hours(bob).await.unwrap(), None);
}

/// `set_quiet_hours` reads back through `quiet_hours` immediately, the same
/// round trip `PUT`/`GET /push/quiet-hours` give a client.
#[tokio::test]
async fn set_quiet_hours_persists_and_reads_back() {
    let (store, _guard) = new_store("slimm-quiet-hours-persist").await;
    let bob = account(&store, "bob").await;

    let window = QuietHours::parse(23 * 60, 8 * 60).unwrap();
    assert!(store.set_quiet_hours(bob, Some(window)).await.unwrap());
    assert_eq!(store.quiet_hours(bob).await.unwrap(), Some(window));

    assert!(store.set_quiet_hours(bob, None).await.unwrap());
    assert_eq!(store.quiet_hours(bob).await.unwrap(), None);
}
