// SPDX-License-Identifier: AGPL-3.0-only
//! `lib.rs`'s own `sweep_stale_voice_calls_at`, driven directly against a
//! fake room service that records what it receives, so a heartbeat going
//! stale is proven to reach a real `RemoveParticipant` call rather than only
//! a status code. Nothing before this exercised the sweep and eviction
//! together at all: a sweep wired to a different `VoiceService` clone would
//! have passed every other test in this crate.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use axum::Router;
use axum::extract::State;
use axum::routing::post;
use axum::{Json, http::StatusCode};
use serde_json::{Value, json};
use slimm_server::ids::{ChannelId, UserId};
use slimm_server::voice::VoiceService;
use tokio::net::TcpListener;

/// A room service that records every `RemoveParticipant` call it receives,
/// rather than just answering one canned response: the point of these tests
/// is proving the call actually arrives, not merely that the handler does
/// not error.
#[derive(Clone, Default)]
struct RecordingRoomService {
    removed: Arc<Mutex<Vec<Value>>>,
}

async fn remove_participant(
    State(recorder): State<RecordingRoomService>,
    Json(body): Json<Value>,
) -> StatusCode {
    recorder.removed.lock().unwrap().push(body);
    StatusCode::OK
}

async fn spawn(recorder: RecordingRoomService) -> String {
    let router = Router::new()
        .route(
            "/twirp/livekit.RoomService/RemoveParticipant",
            post(remove_participant),
        )
        .with_state(recorder);
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, router).await.unwrap();
    });
    format!("http://{addr}")
}

fn voice_at(url: &str) -> VoiceService {
    VoiceService::for_test(url, "APIkey", "a-secret-at-least-32-chars-long!")
}

#[tokio::test]
async fn a_stale_heartbeat_reaches_a_real_remove_participant_call() {
    let recorder = RecordingRoomService::default();
    let url = spawn(recorder.clone()).await;
    let voice = voice_at(&url);

    let user = UserId::generate();
    let channel = ChannelId::generate();
    let start = Instant::now();
    voice.record_heartbeat_at_for_test(user, channel, start);

    // Nothing stale yet: the sweep must find and remove nobody.
    slimm_server::sweep_stale_voice_calls_at(&voice, start).await;
    assert!(recorder.removed.lock().unwrap().is_empty());
    assert!(voice.has_heartbeat_for_test(user, channel));

    // Past the staleness threshold now: the sweep must find and evict it.
    let past = start + Duration::from_secs(41);
    slimm_server::sweep_stale_voice_calls_at(&voice, past).await;

    let removed = recorder.removed.lock().unwrap();
    assert_eq!(removed.len(), 1, "exactly one participant was evicted");
    assert_eq!(removed[0]["identity"], user.to_string());
    assert_eq!(removed[0]["room"], format!("channel-{channel}"));
}

#[tokio::test]
async fn a_swept_entry_is_forgotten_so_a_later_sweep_does_not_re_evict_it() {
    let recorder = RecordingRoomService::default();
    let url = spawn(recorder.clone()).await;
    let voice = voice_at(&url);

    let user = UserId::generate();
    let channel = ChannelId::generate();
    let start = Instant::now();
    voice.record_heartbeat_at_for_test(user, channel, start);

    let past = start + Duration::from_secs(41);
    slimm_server::sweep_stale_voice_calls_at(&voice, past).await;
    slimm_server::sweep_stale_voice_calls_at(&voice, past + Duration::from_secs(1)).await;

    assert_eq!(
        recorder.removed.lock().unwrap().len(),
        1,
        "remove_participant forgetting its own entry is what stops a second \
         sweep rediscovering, and re-evicting, somebody already gone"
    );
}

#[tokio::test]
async fn a_refreshed_heartbeat_is_never_swept_or_evicted() {
    let recorder = RecordingRoomService::default();
    let url = spawn(recorder.clone()).await;
    let voice = voice_at(&url);

    let user = UserId::generate();
    let channel = ChannelId::generate();
    let start = Instant::now();
    voice.record_heartbeat_at_for_test(user, channel, start);
    // A real client's next beat, landing before the old deadline.
    voice.record_heartbeat_at_for_test(user, channel, start + Duration::from_secs(20));

    slimm_server::sweep_stale_voice_calls_at(&voice, start + Duration::from_secs(41)).await;

    assert!(recorder.removed.lock().unwrap().is_empty());
    assert!(voice.has_heartbeat_for_test(user, channel));
}

/// [`json`] is only used to shape the recorded body for the assertions
/// above; this pins that the room service really receives what
/// `remove_participant` sends, not a hand-shaped stand-in for it.
#[tokio::test]
async fn the_recorded_call_carries_no_more_than_room_and_identity() {
    let recorder = RecordingRoomService::default();
    let url = spawn(recorder.clone()).await;
    let voice = voice_at(&url);

    let user = UserId::generate();
    let channel = ChannelId::generate();
    let start = Instant::now();
    voice.record_heartbeat_at_for_test(user, channel, start);
    slimm_server::sweep_stale_voice_calls_at(&voice, start + Duration::from_secs(60)).await;

    let removed = recorder.removed.lock().unwrap();
    let call = &removed[0];
    assert_eq!(
        call,
        &json!({ "room": format!("channel-{channel}"), "identity": user.to_string() })
    );
}
