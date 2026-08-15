// SPDX-License-Identifier: AGPL-3.0-only
//! Deleting several messages as one act, and the four ways that can go wrong
//! quietly.
//!
//! A bulk path that does less than the single one is the failure this file
//! exists for. It cannot be caught by "did the messages disappear" alone, so
//! every case here also checks the thing that is easy to drop and invisible
//! from the transcript: one op per message and no gaps in the sequence, the
//! attachment links released, the audit row written, and nothing at all
//! written when the request is refused.
//!
//! The op-density case is the one worth understanding. Clients apply an op only
//! when its seq is exactly one past their cursor and fall back to a full REST
//! reconcile otherwise, so a batch that allocated one seq for N deletions would
//! be correct in the database and make every connected client resync - the
//! opposite of what a purge is for.

use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use slimm_server::auth::Auth;
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::http::{self, AppState};
use slimm_server::hub::Hub;
use slimm_server::ids::{ChannelId, UserId};
use slimm_server::permissions::Permissions;
use slimm_server::push::PushSender;
use slimm_server::ratelimit::RateLimiter;
use slimm_server::store::Store;
use sqlx::SqlitePool;
use tower::ServiceExt;
use uuid::Uuid;

mod support;

async fn harness() -> (Store, SqlitePool, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new("slimm-bulk-delete");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    (Store::new(pool.clone()), pool, guard)
}

fn app(store: Store) -> Router {
    http::router(AppState {
        store,
        auth: Auth::new(2).unwrap(),
        hub: Hub::new(),
        limiter: RateLimiter::new(),
        push: PushSender::disabled(),
        voice: slimm_server::voice::VoiceService::disabled(),
        media: slimm_server::media::Media::for_tests(),
        gifs: slimm_server::http::gifs::GifSearch::disabled(),
    })
}

fn request(method: &str, uri: &str, token: Option<&str>, body: Option<Value>) -> Request<Body> {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    match body {
        Some(value) => builder
            .header("content-type", "application/json")
            .body(Body::from(value.to_string()))
            .unwrap(),
        None => builder.body(Body::empty()).unwrap(),
    }
}

async fn json_body(response: axum::response::Response) -> Value {
    let bytes = axum::body::to_bytes(response.into_body(), 1 << 20)
        .await
        .unwrap();
    serde_json::from_slice(&bytes).unwrap_or(Value::Null)
}

async fn account(store: &Store, username: &str) -> (String, UserId) {
    let user = store
        .create_account(username, username, "not-a-real-hash")
        .await
        .unwrap();
    let tokens = store.open_session(user.id, "cli").await.unwrap();
    (tokens.access_token, user.id)
}

/// An administrator who owns the deployment, a moderator holding only
/// MANAGE_MESSAGES, and an ordinary member to be moderated.
async fn people(store: &Store) -> ((String, UserId), (String, UserId), (String, UserId)) {
    let admin = account(store, "root").await;
    store.bootstrap_deployment(admin.1).await.unwrap();
    let moderator = account(store, "mod").await;
    let member = account(store, "nia").await;
    let role = store
        .create_role("mods", Permissions::MANAGE_MESSAGES, false)
        .await
        .unwrap();
    store.assign_role(moderator.1, role).await.unwrap();
    (admin, moderator, member)
}

async fn channel_id(store: &Store) -> String {
    store.list_channels().await.unwrap()[0].id.0.to_string()
}

async fn send(app: &Router, channel: &str, token: &str, content: &str) -> String {
    let body = json_body(
        app.clone()
            .oneshot(request(
                "POST",
                &format!("/channels/{channel}/messages"),
                Some(token),
                Some(json!({ "id": Uuid::now_v7().to_string(), "content": content })),
            ))
            .await
            .unwrap(),
    )
    .await;
    body["id"].as_str().unwrap().to_owned()
}

async fn bulk_delete(app: &Router, channel: &str, token: &str, ids: &[String]) -> StatusCode {
    app.clone()
        .oneshot(request(
            "POST",
            &format!("/channels/{channel}/messages/bulk-delete"),
            Some(token),
            Some(json!({ "message_ids": ids })),
        ))
        .await
        .unwrap()
        .status()
}

async fn live_count(store: &Store, channel: &str) -> usize {
    let id = ChannelId(Uuid::parse_str(channel).unwrap());
    store.list_messages(id, None, 100).await.unwrap().len()
}

/// Every delete op this channel has, oldest first, as `(seq, kind)`.
async fn ops(pool: &SqlitePool, channel: &str) -> Vec<(i64, String)> {
    let id = ChannelId(Uuid::parse_str(channel).unwrap());
    sqlx::query_as("SELECT seq, kind FROM message_ops WHERE channel_id = ? ORDER BY seq")
        .bind(id)
        .fetch_all(pool)
        .await
        .expect("read the op stream")
}

async fn audit(pool: &SqlitePool) -> Vec<(String, Option<Vec<u8>>, Option<Vec<u8>>)> {
    sqlx::query_as("SELECT action, actor_id, subject_id FROM moderation_audit_log ORDER BY id")
        .fetch_all(pool)
        .await
        .expect("read the audit log")
}

#[tokio::test]
async fn a_moderator_deletes_several_messages_in_one_request() {
    let (store, pool, _guard) = harness().await;
    let (_admin, moderator, member) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let mut ids = Vec::new();
    for i in 0..3 {
        ids.push(send(&app, &channel, &member.0, &format!("spam {i}")).await);
    }
    send(&app, &channel, &member.0, "kept").await;

    assert_eq!(
        bulk_delete(&app, &channel, &moderator.0, &ids).await,
        StatusCode::NO_CONTENT
    );

    assert_eq!(
        live_count(&store, &channel).await,
        1,
        "only the message that was not named survives"
    );
    let deletes: Vec<_> = ops(&pool, &channel)
        .await
        .into_iter()
        .filter(|(_, kind)| kind == "delete")
        .collect();
    assert_eq!(
        deletes.len(),
        3,
        "one delete op per message, not one per batch"
    );
}

/// The invariant the client's own cursor rule depends on: every op seq in the
/// channel is consecutive, so a live client can apply the burst rather than
/// falling back to a full REST reconcile.
#[tokio::test]
async fn each_deleted_message_takes_its_own_consecutive_seq() {
    let (store, pool, _guard) = harness().await;
    let (_admin, moderator, member) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let mut ids = Vec::new();
    for i in 0..4 {
        ids.push(send(&app, &channel, &member.0, &format!("spam {i}")).await);
    }
    bulk_delete(&app, &channel, &moderator.0, &ids).await;

    let seqs: Vec<i64> = ops(&pool, &channel)
        .await
        .into_iter()
        .map(|(s, _)| s)
        .collect();
    let expected: Vec<i64> = (1..=seqs.len() as i64).collect();
    assert_eq!(
        seqs, expected,
        "the op stream must stay dense; a gap makes every live client resync"
    );
}

/// Deleting an id that is already gone is not an error and writes nothing,
/// the single delete's own idempotence carried over.
#[tokio::test]
async fn an_already_deleted_id_is_skipped_rather_than_re_deleted() {
    let (store, pool, _guard) = harness().await;
    let (_admin, moderator, member) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let id = send(&app, &channel, &member.0, "spam").await;
    let ids = vec![id];
    assert_eq!(
        bulk_delete(&app, &channel, &moderator.0, &ids).await,
        StatusCode::NO_CONTENT
    );
    let after_first = ops(&pool, &channel).await.len();

    assert_eq!(
        bulk_delete(&app, &channel, &moderator.0, &ids).await,
        StatusCode::NO_CONTENT,
        "a repeat is a success, not a 404"
    );
    assert_eq!(
        ops(&pool, &channel).await.len(),
        after_first,
        "and it writes no second op, so no client is told twice"
    );
}

/// Nothing is deleted unless every id resolves, so a batch naming one message
/// from another channel leaves the rest of the batch alone.
#[tokio::test]
async fn an_id_from_another_channel_refuses_the_whole_batch() {
    let (store, pool, _guard) = harness().await;
    let (admin, moderator, member) = people(&store).await;
    let channel = channel_id(&store).await;
    let other = store
        .create_channel("other", "text")
        .await
        .unwrap()
        .id
        .0
        .to_string();
    let app = app(store.clone());

    let here = send(&app, &channel, &member.0, "spam").await;
    let elsewhere = send(&app, &other, &admin.0, "not in this channel").await;

    let status = bulk_delete(&app, &channel, &moderator.0, &[here.clone(), elsewhere]).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    assert_eq!(
        live_count(&store, &channel).await,
        1,
        "the id that was valid must not have been deleted anyway"
    );
    assert!(
        ops(&pool, &channel).await.is_empty(),
        "a refused batch writes no ops at all"
    );
}

/// Containment: a moderator holding only MANAGE_MESSAGES cannot bulk-delete an
/// administrator's message, even though the single delete would let them.
#[tokio::test]
async fn a_batch_naming_an_administrators_message_is_refused() {
    let (store, pool, _guard) = harness().await;
    let (admin, moderator, member) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let theirs = send(&app, &channel, &member.0, "spam").await;
    let admins = send(&app, &channel, &admin.0, "an administrator speaking").await;

    let status = bulk_delete(&app, &channel, &moderator.0, &[theirs, admins]).await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    assert_eq!(
        live_count(&store, &channel).await,
        2,
        "the refusal happens before anything is written"
    );
    assert!(ops(&pool, &channel).await.is_empty());
}

#[tokio::test]
async fn more_ids_than_the_cap_is_refused_rather_than_truncated() {
    let (store, _pool, _guard) = harness().await;
    let (_admin, moderator, _member) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let ids: Vec<String> = (0..65).map(|_| Uuid::now_v7().to_string()).collect();
    assert_eq!(
        bulk_delete(&app, &channel, &moderator.0, &ids).await,
        StatusCode::BAD_REQUEST,
        "over the cap must refuse, never silently delete the first 64"
    );
}

/// The act is recorded, one row per author whose messages were removed, naming
/// the moderator who did it - which is the whole point of 0049.
#[tokio::test]
async fn the_act_is_recorded_against_each_author() {
    let (store, pool, _guard) = harness().await;
    let (_admin, moderator, member) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let a = send(&app, &channel, &member.0, "spam one").await;
    let b = send(&app, &channel, &member.0, "spam two").await;
    bulk_delete(&app, &channel, &moderator.0, &[a, b]).await;

    let rows = audit(&pool).await;
    assert_eq!(
        rows,
        vec![(
            "messages_deleted".to_owned(),
            Some(moderator.1.0.as_bytes().to_vec()),
            Some(member.1.0.as_bytes().to_vec()),
        )],
        "one row for the one author, naming who acted and who it was about"
    );
}

#[tokio::test]
async fn a_refused_batch_records_no_act() {
    let (store, pool, _guard) = harness().await;
    let (admin, moderator, _member) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let admins = send(&app, &channel, &admin.0, "an administrator speaking").await;
    bulk_delete(&app, &channel, &moderator.0, &[admins]).await;

    assert!(
        audit(&pool).await.is_empty(),
        "a refusal is not an act, so the trail must not claim one"
    );
}

/// A member without MANAGE_MESSAGES cannot bulk-delete at all, including their
/// own messages: this route is the moderation verb, and the single delete is
/// still there for an author deleting their own.
#[tokio::test]
async fn bulk_delete_needs_manage_messages_even_for_your_own_messages() {
    let (store, _pool, _guard) = harness().await;
    let (_admin, _moderator, member) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let mine = send(&app, &channel, &member.0, "my own message").await;
    assert_eq!(
        bulk_delete(&app, &channel, &member.0, &[mine]).await,
        StatusCode::FORBIDDEN
    );
    assert_eq!(live_count(&store, &channel).await, 1);
}

/// Deleting a message has to let go of its attachments, or a purge leaves the
/// rows that keep those files alive and nothing ever reclaims them.
///
/// Linked directly rather than through an upload: what is under test is the
/// release, and the upload path has its own tests.
#[tokio::test]
async fn deleting_releases_the_attachments_the_messages_held() {
    let (store, pool, _guard) = harness().await;
    let (_admin, moderator, member) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let id = send(&app, &channel, &member.0, "with a file").await;
    let sha = vec![7u8; 32];
    sqlx::query("INSERT INTO attachments (sha256, size, content_type, created_at) VALUES (?, 1, 'image/png', 1)")
        .bind(sha.clone())
        .execute(&pool)
        .await
        .unwrap();
    sqlx::query("INSERT INTO message_attachments (message_id, sha256, position) VALUES (?, ?, 0)")
        .bind(Uuid::parse_str(&id).unwrap())
        .bind(sha.clone())
        .execute(&pool)
        .await
        .unwrap();

    bulk_delete(&app, &channel, &moderator.0, &[id]).await;

    let links: i64 = sqlx::query_scalar("SELECT count(*) FROM message_attachments")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(links, 0, "the link must be released with the message");
    let rows: i64 = sqlx::query_scalar("SELECT count(*) FROM attachments")
        .fetch_one(&pool)
        .await
        .unwrap();
    assert_eq!(rows, 0, "and the now-unreferenced attachment collected");
}

/// A caller who cannot see the channel is refused before the route ever looks
/// for the messages, so its answer cannot be used to find out whether a channel
/// or a message exists - decision 0011's masking rule.
///
/// Both halves matter and they must be indistinguishable: a real id in a hidden
/// channel and an id that exists nowhere have to come back the same way. This
/// was missing when the route first shipped, and reordering the existence
/// lookup ahead of the permission checks passed every other test in this file.
#[tokio::test]
async fn a_caller_who_cannot_see_the_channel_learns_nothing_from_the_answer() {
    let (store, _pool, _guard) = harness().await;
    let (admin, _moderator, outsider) = people(&store).await;
    let channel = channel_id(&store).await;
    let app = app(store.clone());

    let real = send(&app, &channel, &admin.0, "in a channel you cannot see").await;

    // The everyone role loses VIEW_CHANNEL, so the outsider cannot see it at all.
    let everyone = store
        .list_roles()
        .await
        .unwrap()
        .into_iter()
        .find(|r| r.is_everyone)
        .unwrap();
    store
        .update_role(everyone.id, None, Some(Permissions::NONE))
        .await
        .unwrap();

    let for_real_id = bulk_delete(&app, &channel, &outsider.0, &[real]).await;
    let invented = Uuid::now_v7().to_string();
    let for_invented = bulk_delete(&app, &channel, &outsider.0, &[invented]).await;

    assert_eq!(for_real_id, StatusCode::FORBIDDEN);
    assert_eq!(
        for_real_id, for_invented,
        "a real id and an invented one must answer identically, or the route \
         says which messages exist in a channel the caller cannot see"
    );
}
