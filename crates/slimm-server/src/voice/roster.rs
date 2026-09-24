// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Listing who is connected to a channel's voice room right now.
//!
//! This is the read-only half of [`super::VoiceService`]: unlike minting a
//! token, which is pure local signing, listing participants is a real round
//! trip to the SFU's room service, so it costs exactly what [`super::mint`]
//! does not. The caller decides how often that is worth paying for and who
//! among the result a given viewer may actually be told about; this only
//! reports who the SFU says is connected.

use crate::ids::{ChannelId, UserId};

use super::webhook::is_screen_share_source;
use super::{VoiceError, VoiceService, room_for_channel};

/// One participant the SFU reports as currently connected to a room.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RoomParticipant {
    /// The token's `sub`, the identity LiveKit trusts because we signed it.
    pub user_id: UserId,
    /// The token's `name`, as it was when this participant joined.
    pub display_name: String,
    /// Whether any of this participant's published tracks is screen-share
    /// sourced. Read straight off this same `ListParticipants` response, so
    /// it stays correct even on a deployment with no LiveKit webhook
    /// configured; see `docs/decisions/0032-voice-participant-webhooks.md`.
    pub is_sharing_screen: bool,
    /// Whether any of this participant's published tracks is video, camera
    /// or screen share alike - free from the same response as
    /// `is_sharing_screen`.
    pub has_video: bool,
}

/// The shape of a LiveKit `ListParticipants` twirp response; only the fields
/// this crate reads.
#[derive(serde::Deserialize)]
struct ListParticipantsResponse {
    #[serde(default)]
    participants: Vec<ParticipantInfo>,
}

#[derive(serde::Deserialize)]
struct ParticipantInfo {
    identity: String,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    tracks: Vec<TrackInfo>,
}

#[derive(serde::Deserialize)]
struct TrackInfo {
    #[serde(default)]
    source: String,
    #[serde(rename = "type", default)]
    track_type: String,
}

impl VoiceService {
    /// Lists who is currently connected to a channel's voice room.
    ///
    /// A room nobody has ever joined does not exist yet as far as the SFU is
    /// concerned, and that answers identically to a room that emptied back
    /// out: nobody is there, not an error.
    pub async fn list_participants(
        &self,
        channel_id: ChannelId,
    ) -> Result<Vec<RoomParticipant>, VoiceError> {
        let Some(enabled) = self.inner.as_ref() else {
            return Err(VoiceError::Unavailable);
        };
        let room = room_for_channel(channel_id);
        let admin = self.admin_token(enabled, &room)?;

        let response = enabled
            .http
            .post(format!(
                "{}/twirp/livekit.RoomService/ListParticipants",
                enabled.service_url
            ))
            .bearer_auth(admin)
            .json(&serde_json::json!({ "room": room }))
            .send()
            .await
            .map_err(|e| VoiceError::Internal(e.into()))?;

        // An empty room and a room that was never created answer the same way.
        if response.status() == reqwest::StatusCode::NOT_FOUND {
            return Ok(Vec::new());
        }
        if !response.status().is_success() {
            let status = response.status();
            return Err(VoiceError::Internal(anyhow::anyhow!(
                "livekit room service refused listing participants: {status}"
            )));
        }

        let body: ListParticipantsResponse = response
            .json()
            .await
            .map_err(|e| VoiceError::Internal(e.into()))?;

        Ok(body
            .participants
            .into_iter()
            .filter_map(|p| {
                // Parsed back rather than trusted: mint() set it to this user's id.
                let user_id = UserId(p.identity.parse().ok()?);
                let is_sharing_screen = p.tracks.iter().any(|t| is_screen_share_source(&t.source));
                let has_video = p.tracks.iter().any(|t| t.track_type == "VIDEO");
                Some(RoomParticipant {
                    user_id,
                    display_name: p.name.unwrap_or_default(),
                    is_sharing_screen,
                    has_video,
                })
            })
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use axum::extract::State;
    use axum::routing::post;
    use axum::{Json, Router};
    use serde_json::{Value, json};
    use tokio::net::TcpListener;

    use super::*;

    /// Spawns a stand-in LiveKit room service on an ephemeral loopback port,
    /// answering every `ListParticipants` call with a fixed status and body.
    async fn spawn_room_service(status: axum::http::StatusCode, body: Value) -> String {
        #[derive(Clone)]
        struct Canned {
            status: axum::http::StatusCode,
            body: Value,
        }
        async fn answer(State(canned): State<Canned>) -> (axum::http::StatusCode, Json<Value>) {
            (canned.status, Json(canned.body))
        }
        let router = Router::new()
            .route("/twirp/livekit.RoomService/ListParticipants", post(answer))
            .with_state(Canned { status, body });
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            axum::serve(listener, router).await.unwrap();
        });
        format!("http://{addr}")
    }

    fn service_at(url: &str) -> VoiceService {
        VoiceService::for_test(url, "APIkey", "a-secret-at-least-32-chars-long!")
    }

    #[tokio::test]
    async fn a_disabled_deployment_reports_unavailable_rather_than_calling_out() {
        let result = VoiceService::disabled()
            .list_participants(ChannelId::generate())
            .await;
        assert!(matches!(result, Err(VoiceError::Unavailable)));
    }

    #[tokio::test]
    async fn participants_are_mapped_back_to_the_user_id_that_joined() {
        let alice = UserId::generate();
        let url = spawn_room_service(
            axum::http::StatusCode::OK,
            json!({
                "participants": [
                    { "identity": alice.to_string(), "name": "Alice" },
                ]
            }),
        )
        .await;

        let participants = service_at(&url)
            .list_participants(ChannelId::generate())
            .await
            .expect("the mock room service answered");
        assert_eq!(
            participants,
            vec![RoomParticipant {
                user_id: alice,
                display_name: "Alice".to_owned(),
                is_sharing_screen: false,
                has_video: false,
            }]
        );
    }

    #[tokio::test]
    async fn a_screen_share_track_sets_is_sharing_screen_and_has_video() {
        let alice = UserId::generate();
        let url = spawn_room_service(
            axum::http::StatusCode::OK,
            json!({
                "participants": [
                    {
                        "identity": alice.to_string(),
                        "name": "Alice",
                        "tracks": [
                            { "type": "VIDEO", "source": "SCREEN_SHARE" },
                            { "type": "AUDIO", "source": "SCREEN_SHARE_AUDIO" },
                        ],
                    },
                ]
            }),
        )
        .await;

        let participants = service_at(&url)
            .list_participants(ChannelId::generate())
            .await
            .expect("the mock room service answered");
        assert_eq!(
            participants,
            vec![RoomParticipant {
                user_id: alice,
                display_name: "Alice".to_owned(),
                is_sharing_screen: true,
                has_video: true,
            }]
        );
    }

    #[tokio::test]
    async fn a_camera_track_sets_has_video_without_screen_sharing() {
        let alice = UserId::generate();
        let url = spawn_room_service(
            axum::http::StatusCode::OK,
            json!({
                "participants": [
                    {
                        "identity": alice.to_string(),
                        "name": "Alice",
                        "tracks": [{ "type": "VIDEO", "source": "CAMERA" }],
                    },
                ]
            }),
        )
        .await;

        let participants = service_at(&url)
            .list_participants(ChannelId::generate())
            .await
            .expect("the mock room service answered");
        assert!(participants[0].has_video);
        assert!(!participants[0].is_sharing_screen);
    }

    #[tokio::test]
    async fn a_room_that_was_never_created_is_empty_not_an_error() {
        let url = spawn_room_service(axum::http::StatusCode::NOT_FOUND, json!({})).await;
        let participants = service_at(&url)
            .list_participants(ChannelId::generate())
            .await
            .expect("a missing room is an empty room, not a failure");
        assert!(participants.is_empty());
    }

    #[tokio::test]
    async fn an_identity_that_is_not_a_user_id_is_dropped_not_surfaced() {
        let url = spawn_room_service(
            axum::http::StatusCode::OK,
            json!({
                "participants": [
                    { "identity": "not-a-uuid", "name": "Ghost" },
                ]
            }),
        )
        .await;
        let participants = service_at(&url)
            .list_participants(ChannelId::generate())
            .await
            .expect("a malformed identity must not fail the whole list");
        assert!(participants.is_empty());
    }

    #[tokio::test]
    async fn an_upstream_failure_is_reported_rather_than_silently_empty() {
        let url = spawn_room_service(
            axum::http::StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": "boom" }),
        )
        .await;
        let result = service_at(&url)
            .list_participants(ChannelId::generate())
            .await;
        assert!(matches!(result, Err(VoiceError::Internal(_))));
    }
}
