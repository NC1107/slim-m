// SPDX-License-Identifier: AGPL-3.0-only
//! Quiet hours (migration 0056): a per-account time-of-day window that
//! narrows an `everything` notification preference to `mentions`, enforced
//! in `push::recipients::narrow_for_notification_preference` - the same
//! choke point `tests/notification_preference.rs` already drives directly.
//!
//! Windows here are built around the real current UTC minute rather than a
//! fixed clock, since the store has no injectable clock: `around_now`
//! guarantees the window actually contains "now" regardless of when this
//! test happens to run, including across a midnight rollover, without
//! needing to fake the wall clock.

use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::ids::{DeviceId, UserId};
use slimm_server::notifications::{
    MINUTES_PER_DAY, NotificationPreference, QuietHours, minute_of_day_utc,
};
use slimm_server::store::{PushRegistration, Store};

mod support;
use support::wake_recipients;

const KEY: [u8; 32] = [7u8; 32];

fn now_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_millis() as i64
}

fn wrap(minute: i64) -> u16 {
    minute.rem_euclid(i64::from(MINUTES_PER_DAY)) as u16
}

/// A window guaranteed to contain the current UTC minute, whichever side of
/// midnight it falls on: five minutes either side of now, expressed as
/// `start_minute`/`end_minute` the way the wire and `QuietHours::parse`
/// expect.
fn around_now() -> (i64, i64) {
    let now = i64::from(minute_of_day_utc(now_ms()));
    (i64::from(wrap(now - 5)), i64::from(wrap(now + 5)))
}

/// A window guaranteed to exclude the current UTC minute: ten minutes wide,
/// starting fifteen minutes from now, on the far side of `around_now`'s
/// span.
fn away_from_now() -> (i64, i64) {
    let now = i64::from(minute_of_day_utc(now_ms()));
    (i64::from(wrap(now + 15)), i64::from(wrap(now + 25)))
}

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

async fn account(store: &Store, username: &str) -> (UserId, DeviceId) {
    let account = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    store.bootstrap_deployment(account.id).await.unwrap();
    let session = store.open_session(account.id, "phone").await.unwrap();
    (account.id, session.device_id)
}

async fn register(store: &Store, user: UserId, device: DeviceId, token: &str) {
    store
        .register_push(
            user,
            device,
            PushRegistration {
                platform: "ios",
                push_token: token,
                voip_push_token: None,
                push_public_key: &KEY,
                include_content: false,
            },
        )
        .await
        .unwrap();
}

/// A fresh account has no quiet hours, the same "nothing set yet" default
/// every other notification setting keeps on upgrade.
#[tokio::test]
async fn a_fresh_account_has_no_quiet_hours() {
    let (store, _guard) = new_store("slimm-quiet-hours-default").await;
    let (bob, _) = account(&store, "bob").await;
    assert_eq!(store.quiet_hours(bob).await.unwrap(), None);
}

/// `set_quiet_hours` reads back through `quiet_hours` immediately, the same
/// round trip `PUT`/`GET /push/quiet-hours` give a client.
#[tokio::test]
async fn set_quiet_hours_persists_and_reads_back() {
    let (store, _guard) = new_store("slimm-quiet-hours-persist").await;
    let (bob, _) = account(&store, "bob").await;

    let window = QuietHours::parse(23 * 60, 8 * 60).unwrap();
    assert!(store.set_quiet_hours(bob, Some(window)).await.unwrap());
    assert_eq!(store.quiet_hours(bob).await.unwrap(), Some(window));

    assert!(store.set_quiet_hours(bob, None).await.unwrap());
    assert_eq!(store.quiet_hours(bob).await.unwrap(), None);
}

/// Inside the window, an `everything` recipient is suppressed for a plain
/// message: the whole point of the feature, exercised through the real
/// `message_recipients` pipeline rather than `QuietHours::contains` alone.
#[tokio::test]
async fn an_in_window_everything_recipient_is_suppressed_for_a_plain_message() {
    let (store, _guard) = new_store("slimm-quiet-hours-suppress-plain").await;
    let (alice, alice_device) = account(&store, "alice").await;
    let (bob, bob_device) = account(&store, "bob").await;
    let channel = store.list_channels().await.unwrap()[0].id;
    register(&store, alice, alice_device, "alice-token").await;
    register(&store, bob, bob_device, "bob-token").await;

    let (start, end) = around_now();
    let window = QuietHours::parse(start, end).unwrap();
    assert!(store.set_quiet_hours(bob, Some(window)).await.unwrap());

    let recipients = wake_recipients(&store, channel, alice, "just chatting")
        .await
        .unwrap();
    assert!(
        !recipients.contains(&bob),
        "bob is inside his own quiet window, got {recipients:?}"
    );
}

/// Inside the same window, a real `@`-mention still lands: quiet hours
/// narrows `everything` to `mentions`, never to `nothing`.
#[tokio::test]
async fn an_in_window_everything_recipient_still_gets_a_mention() {
    let (store, _guard) = new_store("slimm-quiet-hours-mention-still-lands").await;
    let (alice, alice_device) = account(&store, "alice").await;
    let (bob, bob_device) = account(&store, "bob").await;
    let channel = store.list_channels().await.unwrap()[0].id;
    register(&store, alice, alice_device, "alice-token").await;
    register(&store, bob, bob_device, "bob-token").await;

    let (start, end) = around_now();
    let window = QuietHours::parse(start, end).unwrap();
    assert!(store.set_quiet_hours(bob, Some(window)).await.unwrap());

    let recipients = wake_recipients(&store, channel, alice, "hey @bob look")
        .await
        .unwrap();
    assert!(
        recipients.contains(&bob),
        "a direct mention must still wake a quiet-hours recipient, got {recipients:?}"
    );
}

/// A window that does not contain the current minute changes nothing: an
/// `everything` recipient outside their own quiet hours still gets a plain
/// message, exactly as if no window were set.
#[tokio::test]
async fn a_window_that_does_not_contain_now_changes_nothing() {
    let (store, _guard) = new_store("slimm-quiet-hours-outside-window").await;
    let (alice, alice_device) = account(&store, "alice").await;
    let (bob, bob_device) = account(&store, "bob").await;
    let channel = store.list_channels().await.unwrap()[0].id;
    register(&store, alice, alice_device, "alice-token").await;
    register(&store, bob, bob_device, "bob-token").await;

    let (start, end) = away_from_now();
    let window = QuietHours::parse(start, end).unwrap();
    assert!(store.set_quiet_hours(bob, Some(window)).await.unwrap());

    let recipients = wake_recipients(&store, channel, alice, "just chatting")
        .await
        .unwrap();
    assert!(
        recipients.contains(&bob),
        "bob's quiet window has not started yet, got {recipients:?}"
    );
}

/// Quiet hours only ever narrows `everything`: a recipient who already
/// chose `nothing` is unaffected either way, in the window or out of it.
#[tokio::test]
async fn quiet_hours_never_touches_an_account_that_already_chose_nothing() {
    let (store, _guard) = new_store("slimm-quiet-hours-nothing-unaffected").await;
    let (alice, alice_device) = account(&store, "alice").await;
    let (bob, bob_device) = account(&store, "bob").await;
    let channel = store.list_channels().await.unwrap()[0].id;
    register(&store, alice, alice_device, "alice-token").await;
    register(&store, bob, bob_device, "bob-token").await;
    assert!(
        store
            .set_notification_preference(bob, NotificationPreference::Nothing)
            .await
            .unwrap()
    );

    let (start, end) = around_now();
    let window = QuietHours::parse(start, end).unwrap();
    assert!(store.set_quiet_hours(bob, Some(window)).await.unwrap());

    let recipients = wake_recipients(&store, channel, alice, "hey @bob look")
        .await
        .unwrap();
    assert!(
        !recipients.contains(&bob),
        "nothing stays nothing even inside a quiet window, got {recipients:?}"
    );
}
