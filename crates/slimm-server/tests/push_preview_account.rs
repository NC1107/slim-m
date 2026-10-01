// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The push preview choice lives on the account: a registration that does not
//! state it inherits, an explicit one is saved for every later device, and an
//! account that never chose gets `DEFAULT_PUSH_PREVIEW`.

use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::ids::{DeviceId, UserId};
use slimm_server::notifications::DEFAULT_PUSH_PREVIEW;
use slimm_server::store::{PushRegistration, Store};

mod support;

async fn store() -> (Store, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-push-preview-account");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool), guard)
}

async fn register(s: &Store, user: UserId, device: DeviceId, token: &str, choice: Option<bool>) {
    s.register_push(
        user,
        device,
        PushRegistration {
            platform: "ios",
            push_token: token,
            voip_push_token: None,
            push_public_key: &[0xAA; 32],
            include_content: choice,
        },
    )
    .await
    .unwrap();
}

async fn sealed_for(s: &Store, user: UserId) -> Vec<bool> {
    let mut flags: Vec<bool> = s
        .push_targets(&[user])
        .await
        .unwrap()
        .iter()
        .map(|t| t.include_content)
        .collect();
    flags.sort();
    flags
}

#[tokio::test]
async fn an_account_that_never_chose_gets_the_default() {
    let (s, _guard) = store().await;
    let alice = s.create_user("alice", "Alice").await.unwrap();
    let session = s.open_session(alice.id, "phone").await.unwrap();

    register(&s, alice.id, session.device_id, "t1", None).await;

    assert_eq!(
        s.push_preview(alice.id).await.unwrap(),
        Some(DEFAULT_PUSH_PREVIEW)
    );
    assert_eq!(sealed_for(&s, alice.id).await, vec![DEFAULT_PUSH_PREVIEW]);
}

#[tokio::test]
async fn an_explicit_choice_is_saved_and_a_new_device_inherits_it() {
    let (s, _guard) = store().await;
    let alice = s.create_user("alice", "Alice").await.unwrap();
    let first = s.open_session(alice.id, "phone").await.unwrap();
    register(
        &s,
        alice.id,
        first.device_id,
        "t1",
        Some(!DEFAULT_PUSH_PREVIEW),
    )
    .await;

    let reinstall = s.open_session(alice.id, "phone again").await.unwrap();
    register(&s, alice.id, reinstall.device_id, "t2", None).await;

    assert_eq!(
        s.push_preview(alice.id).await.unwrap(),
        Some(!DEFAULT_PUSH_PREVIEW)
    );
    assert_eq!(
        sealed_for(&s, alice.id).await,
        vec![!DEFAULT_PUSH_PREVIEW, !DEFAULT_PUSH_PREVIEW]
    );
}

#[tokio::test]
async fn a_later_explicit_choice_replaces_the_earlier_one_on_every_device() {
    let (s, _guard) = store().await;
    let alice = s.create_user("alice", "Alice").await.unwrap();
    let a = s.open_session(alice.id, "phone").await.unwrap();
    let b = s.open_session(alice.id, "tablet").await.unwrap();
    register(&s, alice.id, a.device_id, "t1", Some(false)).await;
    register(&s, alice.id, b.device_id, "t2", None).await;

    register(&s, alice.id, b.device_id, "t2", Some(true)).await;
    assert_eq!(sealed_for(&s, alice.id).await, vec![true, true]);

    assert!(s.set_push_preview(alice.id, false).await.unwrap());
    assert_eq!(s.push_preview(alice.id).await.unwrap(), Some(false));
    assert_eq!(sealed_for(&s, alice.id).await, vec![false, false]);
}

#[tokio::test]
async fn one_accounts_choice_never_reaches_another() {
    let (s, _guard) = store().await;
    let alice = s.create_user("alice", "Alice").await.unwrap();
    let bob = s.create_user("bob", "Bob").await.unwrap();
    let a = s.open_session(alice.id, "phone").await.unwrap();
    let b = s.open_session(bob.id, "phone").await.unwrap();

    register(&s, alice.id, a.device_id, "t1", Some(!DEFAULT_PUSH_PREVIEW)).await;
    register(&s, bob.id, b.device_id, "t2", None).await;

    assert_eq!(
        s.push_preview(bob.id).await.unwrap(),
        Some(DEFAULT_PUSH_PREVIEW)
    );
}
