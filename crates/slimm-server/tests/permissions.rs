// SPDX-License-Identifier: AGPL-3.0-only
//! Integration tests for the permission evaluator against a real db, exercising
//! the load-and-evaluate path and the precedence rules end to end.

use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::permissions::Permissions;
use slimm_server::store::Store;

async fn store() -> Store {
    let path = format!("/tmp/slimm-perm-test-{}.db", uuid::Uuid::now_v7());
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

const VIEW: Permissions = Permissions::VIEW_CHANNEL;
const SEND: Permissions = Permissions::SEND_MESSAGES;
const NONE: Permissions = Permissions::NONE;

#[tokio::test]
async fn deny_by_default_with_no_roles() {
    let s = store().await;
    let user = s.create_user("nia", "Nia").await.unwrap();
    let channel = s.create_channel("general", "text").await.unwrap();

    let perms = s.permissions_in_channel(user.id, channel.id).await.unwrap();
    assert_eq!(perms, NONE);
    assert!(!s.has_permission(user.id, channel.id, SEND).await.unwrap());
}

#[tokio::test]
async fn everyone_base_applies_without_explicit_assignment() {
    let s = store().await;
    let user = s.create_user("omar", "Omar").await.unwrap();
    let channel = s.create_channel("general", "text").await.unwrap();
    s.create_role("everyone", VIEW.union(SEND), true)
        .await
        .unwrap();

    // The user holds no explicit role, but @everyone applies to all members.
    let perms = s.permissions_in_channel(user.id, channel.id).await.unwrap();
    assert!(perms.contains(VIEW));
    assert!(perms.contains(SEND));
}

#[tokio::test]
async fn explicit_role_unions_onto_the_base() {
    let s = store().await;
    let user = s.create_user("pia", "Pia").await.unwrap();
    let channel = s.create_channel("general", "text").await.unwrap();
    s.create_role("everyone", VIEW.union(SEND), true)
        .await
        .unwrap();
    let mods = s
        .create_role("mods", Permissions::MANAGE_MESSAGES, false)
        .await
        .unwrap();
    s.assign_role(user.id, mods).await.unwrap();

    let perms = s.permissions_in_channel(user.id, channel.id).await.unwrap();
    assert!(perms.contains(VIEW));
    assert!(perms.contains(Permissions::MANAGE_MESSAGES));
    // base_permissions ignores channels but should agree on the role union.
    let base = s.base_permissions(user.id).await.unwrap();
    assert!(base.contains(Permissions::MANAGE_MESSAGES));
}

#[tokio::test]
async fn administrator_bypasses_channel_denies() {
    let s = store().await;
    let user = s.create_user("quinn", "Quinn").await.unwrap();
    let channel = s.create_channel("general", "text").await.unwrap();
    let everyone = s.create_role("everyone", NONE, true).await.unwrap();
    let admins = s
        .create_role("admins", Permissions::ADMINISTRATOR, false)
        .await
        .unwrap();
    s.assign_role(user.id, admins).await.unwrap();
    // A channel deny on @everyone must not touch an administrator.
    s.set_role_overwrite(channel.id, everyone, NONE, Permissions::ALL)
        .await
        .unwrap();

    let perms = s.permissions_in_channel(user.id, channel.id).await.unwrap();
    assert_eq!(perms, Permissions::ALL);
    assert!(
        s.has_permission(user.id, channel.id, Permissions::BAN_MEMBERS)
            .await
            .unwrap()
    );
}

#[tokio::test]
async fn everyone_channel_overwrite_removes_a_base_permission() {
    let s = store().await;
    let user = s.create_user("rae", "Rae").await.unwrap();
    let channel = s.create_channel("general", "text").await.unwrap();
    let everyone = s
        .create_role("everyone", VIEW.union(SEND), true)
        .await
        .unwrap();
    s.set_role_overwrite(channel.id, everyone, NONE, SEND)
        .await
        .unwrap();

    // In this channel SEND is denied, but the guild base still carries it.
    let perms = s.permissions_in_channel(user.id, channel.id).await.unwrap();
    assert!(perms.contains(VIEW));
    assert!(!perms.contains(SEND));
    assert!(s.base_permissions(user.id).await.unwrap().contains(SEND));
}

#[tokio::test]
async fn role_overwrite_deny_wins_then_member_overwrite_regrants() {
    let s = store().await;
    let user = s.create_user("sol", "Sol").await.unwrap();
    let channel = s.create_channel("general", "text").await.unwrap();
    s.create_role("everyone", VIEW, true).await.unwrap();
    let a = s.create_role("a", NONE, false).await.unwrap();
    let b = s.create_role("b", NONE, false).await.unwrap();
    s.assign_role(user.id, a).await.unwrap();
    s.assign_role(user.id, b).await.unwrap();
    // Role a allows SEND in the channel, role b denies it. Deny wins.
    s.set_role_overwrite(channel.id, a, SEND, NONE)
        .await
        .unwrap();
    s.set_role_overwrite(channel.id, b, NONE, SEND)
        .await
        .unwrap();

    assert!(!s.has_permission(user.id, channel.id, SEND).await.unwrap());

    // A member overwrite grants it back absolutely.
    s.set_member_overwrite(channel.id, user.id, SEND, NONE)
        .await
        .unwrap();
    assert!(s.has_permission(user.id, channel.id, SEND).await.unwrap());
}

#[tokio::test]
async fn only_one_everyone_role_is_allowed() {
    let s = store().await;
    s.create_role("everyone", VIEW, true).await.unwrap();
    // A second @everyone role is rejected by the database constraint.
    assert!(
        s.create_role("everyone-again", SEND, true).await.is_err(),
        "a second @everyone role must be rejected"
    );
    // Ordinary roles are unaffected.
    assert!(s.create_role("mods", SEND, false).await.is_ok());
}

#[tokio::test]
async fn overwrites_for_other_targets_are_ignored() {
    let s = store().await;
    let user = s.create_user("tam", "Tam").await.unwrap();
    let other = s.create_user("uma", "Uma").await.unwrap();
    let channel = s.create_channel("general", "text").await.unwrap();
    s.create_role("everyone", VIEW.union(SEND), true)
        .await
        .unwrap();
    // A role the user does not hold, and a member overwrite for someone else.
    // Neither should touch this user's result.
    let ghost = s.create_role("ghost", NONE, false).await.unwrap();
    s.set_role_overwrite(channel.id, ghost, NONE, SEND)
        .await
        .unwrap();
    s.set_member_overwrite(channel.id, other.id, NONE, SEND)
        .await
        .unwrap();

    let perms = s.permissions_in_channel(user.id, channel.id).await.unwrap();
    assert!(perms.contains(SEND), "another target's deny must not apply");
}
