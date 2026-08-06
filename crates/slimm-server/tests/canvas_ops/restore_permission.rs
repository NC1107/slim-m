// SPDX-License-Identifier: AGPL-3.0-only
//! `restore`'s authorization once the actor's own `MANAGE_CANVAS` has moved
//! since the op it targets was written.
//!
//! Split out of `restore.rs`, which crossed the 500-line hard limit once
//! these landed: bare authorship of a `remove` or `clear` op must not
//! outlive the permission that op needed to create in the first place, or
//! revoking a moderator's canvas bit leaves them able to keep reversing
//! their own past bulk moderation forever.

use axum::http::StatusCode;
use slimm_server::permissions::Permissions;

use crate::fixtures::{
    app, clear, general, id, member, new_store_and_pool, post_object, register, remove, restore,
    stroke, submit_op,
};

async fn is_live(pool: &sqlx::SqlitePool, object_id: &str) -> bool {
    let deleted_at: Option<i64> =
        sqlx::query_scalar("SELECT deleted_at FROM canvas_objects WHERE id = ?")
            .bind(uuid::Uuid::parse_str(object_id).unwrap())
            .fetch_one(pool)
            .await
            .unwrap();
    deleted_at.is_none()
}

/// A `clear` is a bulk moderation act with no notion of "self" content, so
/// the actor who ran it must still hold `MANAGE_CANVAS` to undo it later -
/// mere authorship of the original `clear` must not be enough once that bit
/// is gone, or revoking a moderator's canvas power leaves them able to keep
/// reversing their own past bulk moderation forever.
#[tokio::test]
async fn a_demoted_moderator_cannot_restore_their_own_clear() {
    let (store, pool, _guard) = new_store_and_pool().await;
    let (root_token, _root_id) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store.clone());
    let (bob_token, bob_id) = member(&store, "bob").await;

    let (_, placed) = post_object(&app, channel, &root_token, stroke(&id())).await;
    let object_id = placed["id"].as_str().unwrap().to_owned();

    let mods = store
        .create_role("mods", Permissions::MANAGE_CANVAS, false)
        .await
        .unwrap();
    store.assign_role(bob_id, mods).await.unwrap();

    let clear_op = id();
    let (status, body) = submit_op(&app, channel, &bob_token, clear(&clear_op, 100)).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert!(!is_live(&pool, &object_id).await, "cleared as a moderator");

    store.unassign_role(bob_id, mods).await.unwrap();

    let (status, body) = submit_op(&app, channel, &bob_token, restore(&id(), &clear_op)).await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "bob authored the clear but no longer holds MANAGE_CANVAS: {body}"
    );
    assert!(
        !is_live(&pool, &object_id).await,
        "a refused restore must not have revived the object"
    );

    let (status, body) = submit_op(&app, channel, &root_token, restore(&id(), &clear_op)).await;
    assert_eq!(
        status,
        StatusCode::CREATED,
        "an administrator may still restore it: {body}"
    );
    assert!(is_live(&pool, &object_id).await);
}

/// The same gate, on the narrower `remove` shape: a moderator who removed
/// somebody else's object needed `MANAGE_CANVAS` to do it, so restoring that
/// removal later must ask the same question again rather than accepting
/// bare authorship of the op once the bit is gone.
#[tokio::test]
async fn a_demoted_moderator_cannot_restore_their_removal_of_someone_elses_object() {
    let (store, pool, _guard) = new_store_and_pool().await;
    let (root_token, _root_id) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store.clone());
    let (bob_token, bob_id) = member(&store, "bob").await;

    let (_, placed) = post_object(&app, channel, &root_token, stroke(&id())).await;
    let object_id = placed["id"].as_str().unwrap().to_owned();

    let mods = store
        .create_role("mods", Permissions::MANAGE_CANVAS, false)
        .await
        .unwrap();
    store.assign_role(bob_id, mods).await.unwrap();

    let remove_op = id();
    let (status, body) =
        submit_op(&app, channel, &bob_token, remove(&remove_op, &[&object_id])).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");

    store.unassign_role(bob_id, mods).await.unwrap();

    let (status, body) = submit_op(&app, channel, &bob_token, restore(&id(), &remove_op)).await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "bob removed root's object as a moderator but no longer holds MANAGE_CANVAS: {body}"
    );
    assert!(!is_live(&pool, &object_id).await);
}

/// A member may always restore a removal of their own object, with or
/// without `MANAGE_CANVAS`, since that removal never needed the bit either -
/// self-service undo of your own content must survive a role change that
/// never touched it.
#[tokio::test]
async fn restoring_your_own_object_needs_no_role_at_all() {
    let (store, pool, _guard) = new_store_and_pool().await;
    let (_root_token, _root_id) = register(&store, "root").await;
    let channel = general(&store).await;
    let app = app(store.clone());
    let (bob_token, _bob_id) = member(&store, "bob").await;

    let (_, placed) = post_object(&app, channel, &bob_token, stroke(&id())).await;
    let object_id = placed["id"].as_str().unwrap().to_owned();
    let remove_op = id();
    submit_op(&app, channel, &bob_token, remove(&remove_op, &[&object_id])).await;

    let (status, body) = submit_op(&app, channel, &bob_token, restore(&id(), &remove_op)).await;
    assert_eq!(status, StatusCode::CREATED, "{body}");
    assert!(is_live(&pool, &object_id).await);
}
