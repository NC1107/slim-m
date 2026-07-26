// SPDX-License-Identifier: AGPL-3.0-only
//! LiveKit room access: minting the capability tokens a client joins with, and
//! evicting somebody who should no longer be in a room.
//!
//! [`VoiceService`] is a two-state thing rather than an error path, the same
//! shape as [`crate::push::PushSender`]. A text-only self-host is a supported
//! way to run this and should not have to stand up an SFU, so an unconfigured
//! deployment simply reports that voice is unavailable.
//!
//! Three things about the token matter more than the rest:
//!
//! - **The room name is derived here, never taken from the client.** It is a
//!   pure function of the channel id ([`room_for_channel`]), so asking for a
//!   token is asking for a specific channel and the permission check that
//!   follows is about that channel. A client-supplied room name would let
//!   somebody with voice rights in one channel mint a token for another.
//! - **The grants are derived from the permission bitfield**, not from a role
//!   name or a flag: `CONNECT` is what lets you in at all, `SPEAK` is what
//!   lets you publish, `USE_CANVAS` is what lets you send data. Someone with
//!   listen-only rights gets a token that cannot publish, so the SFU enforces
//!   it too rather than trusting the client to hide a button.
//! - **The TTL is short.** A LiveKit token is a bearer credential the server
//!   cannot revoke once handed out, so a kicked participant is removed through
//!   the room service ([`VoiceService::remove_participant`]) and their token
//!   expires quickly enough that re-joining means asking again, and being
//!   re-checked.

use std::time::{SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use base64::engine::general_purpose::URL_SAFE_NO_PAD as BASE64URL;
use hmac::{Hmac, Mac};
use serde::Serialize;
use sha2::Sha256;

use crate::config::Config;
use crate::ids::{ChannelId, UserId};
use crate::permissions::Permissions;

/// How long a join token is good for.
///
/// Short on purpose: this is a bearer credential, so the window in which a
/// participant removed from a room could walk back in with the same token is
/// exactly this long. Long enough to cover a slow join and a reconnect,
/// nowhere near long enough to be worth saving.
const TOKEN_TTL_SECS: u64 = 120;

/// The SFU accepts this token without asking us, so the TTL is the only thing
/// bounding how long a removed participant could rejoin with one they already
/// hold. Enforced at compile time so raising it is a deliberate act.
const _: () = assert!(TOKEN_TTL_SECS <= 300);

/// How long the server's own room-admin token is good for. Only ever used for
/// one immediate call, so it needs no room to spare.
const ADMIN_TOKEN_TTL_SECS: u64 = 30;

/// A minted room credential, and everything the client needs to use it.
#[derive(Debug, Clone, Serialize)]
pub struct RoomToken {
    /// The SFU to connect to.
    pub url: String,
    /// The room to join. Derived from the channel, echoed so the client does
    /// not have to know the derivation rule.
    pub room: String,
    pub token: String,
    /// Unix milliseconds, so a client can re-mint before it lapses rather
    /// than discovering the expiry by being disconnected.
    pub expires_at: i64,
    /// Whether this token allows publishing audio, so the UI can show a
    /// listen-only state up front instead of after the SFU refuses.
    pub can_publish: bool,
}

/// Why a token could not be minted.
#[derive(Debug)]
pub enum VoiceError {
    /// This deployment has no SFU configured, so it has no voice at all.
    Unavailable,
    Internal(anyhow::Error),
}

impl From<anyhow::Error> for VoiceError {
    fn from(err: anyhow::Error) -> Self {
        VoiceError::Internal(err)
    }
}

/// The room a channel's voice happens in.
///
/// A pure function of the channel id, so it is stable across restarts and
/// impossible for a client to influence.
pub fn room_for_channel(channel_id: ChannelId) -> String {
    format!("channel-{channel_id}")
}

/// Mints LiveKit room tokens and evicts participants.
#[derive(Clone)]
pub struct VoiceService {
    inner: Option<std::sync::Arc<Enabled>>,
}

struct Enabled {
    url: String,
    api_key: String,
    api_secret: String,
    http: reqwest::Client,
    /// The room service base, derived from the client URL by swapping the
    /// WebSocket scheme for its HTTP equivalent. LiveKit serves both on the
    /// same host, and deriving it means one setting instead of two that can
    /// disagree.
    service_url: String,
}

impl VoiceService {
    /// Builds a service from config. Disabled unless the URL, key, and secret
    /// are all present, and logs which of the two it is once at startup.
    pub fn new(config: &Config) -> anyhow::Result<Self> {
        let inner = match (
            &config.livekit_url,
            &config.livekit_api_key,
            &config.livekit_api_secret,
        ) {
            (Some(url), Some(key), Some(secret)) => {
                let service_url = http_url_for(url)?;
                tracing::info!(%url, "voice enabled");
                Some(std::sync::Arc::new(Enabled {
                    url: url.clone(),
                    api_key: key.clone(),
                    api_secret: secret.clone(),
                    http: reqwest::Client::builder()
                        .timeout(std::time::Duration::from_secs(5))
                        .build()
                        .expect("building the livekit room service client"),
                    service_url,
                }))
            }
            _ => {
                tracing::info!(
                    "SLIMM_LIVEKIT_URL / _API_KEY / _API_SECRET not all set; voice is disabled"
                );
                None
            }
        };
        Ok(Self { inner })
    }

    /// A service with no SFU behind it, for tests and text-only deployments.
    pub fn disabled() -> Self {
        Self { inner: None }
    }

    /// A service wired to an explicit key and secret, for tests that need to
    /// inspect a real signed token without standing up an SFU.
    pub fn for_test(url: &str, api_key: &str, api_secret: &str) -> Self {
        Self {
            inner: Some(std::sync::Arc::new(Enabled {
                url: url.to_owned(),
                api_key: api_key.to_owned(),
                api_secret: api_secret.to_owned(),
                http: reqwest::Client::new(),
                service_url: http_url_for(url).expect("test url"),
            })),
        }
    }

    pub fn is_enabled(&self) -> bool {
        self.inner.is_some()
    }

    /// Mints a join token for `user_id` in `channel_id`.
    ///
    /// The caller is responsible for having checked that the user may connect;
    /// what this does is turn the permissions it is handed into the matching
    /// SFU grants, so the two cannot drift apart at the call site.
    pub fn mint(
        &self,
        channel_id: ChannelId,
        user_id: UserId,
        permissions: Permissions,
        display_name: &str,
    ) -> Result<RoomToken, VoiceError> {
        let Some(enabled) = self.inner.as_ref() else {
            return Err(VoiceError::Unavailable);
        };

        let room = room_for_channel(channel_id);
        let can_publish = permissions.contains(Permissions::SPEAK);
        let can_publish_data = permissions.contains(Permissions::USE_CANVAS);
        let now = unix_secs();
        let expires = now + TOKEN_TTL_SECS;

        let grants = VideoGrant {
            room: room.clone(),
            room_join: true,
            can_subscribe: true,
            can_publish,
            can_publish_data,
            // Nothing about a participant's own metadata is trusted, and the
            // display name is set from the token below, so there is no reason
            // for a client to be able to rewrite it mid-call.
            can_update_own_metadata: false,
            room_admin: false,
        };

        let token = self.sign(
            enabled,
            Claims {
                iss: &enabled.api_key,
                sub: &user_id.to_string(),
                name: Some(display_name),
                nbf: now,
                exp: expires,
                video: grants,
            },
        )?;

        Ok(RoomToken {
            url: enabled.url.clone(),
            room,
            token,
            expires_at: (expires as i64) * 1000,
            can_publish,
        })
    }

    /// Removes a participant from a channel's room immediately.
    ///
    /// Used when somebody loses the right to be there, which a token they
    /// already hold would otherwise let them keep exercising until it lapses.
    /// Best-effort by design: it is called from paths whose real work has
    /// already committed, so a failure is logged rather than propagated, and
    /// the short token TTL is the backstop.
    pub async fn remove_participant(
        &self,
        channel_id: ChannelId,
        user_id: UserId,
    ) -> Result<(), VoiceError> {
        let Some(enabled) = self.inner.as_ref() else {
            return Err(VoiceError::Unavailable);
        };
        let room = room_for_channel(channel_id);
        let now = unix_secs();
        let admin = self.sign(
            enabled,
            Claims {
                iss: &enabled.api_key,
                sub: "slim-m-server",
                name: None,
                nbf: now,
                exp: now + ADMIN_TOKEN_TTL_SECS,
                video: VideoGrant {
                    room: room.clone(),
                    room_admin: true,
                    room_join: false,
                    can_subscribe: false,
                    can_publish: false,
                    can_publish_data: false,
                    can_update_own_metadata: false,
                },
            },
        )?;

        let response = enabled
            .http
            .post(format!(
                "{}/twirp/livekit.RoomService/RemoveParticipant",
                enabled.service_url
            ))
            .bearer_auth(admin)
            .json(&serde_json::json!({ "room": room, "identity": user_id.to_string() }))
            .send()
            .await
            .map_err(|e| VoiceError::Internal(e.into()))?;

        if !response.status().is_success() {
            let status = response.status();
            // A participant who is not in the room is the ordinary case when
            // somebody is kicked while not in a call, so it is not an error.
            if status == reqwest::StatusCode::NOT_FOUND {
                return Ok(());
            }
            return Err(VoiceError::Internal(anyhow::anyhow!(
                "livekit room service refused the eviction: {status}"
            )));
        }
        Ok(())
    }

    /// Signs a claim set as an HS256 JWT, which is the format LiveKit takes.
    fn sign(&self, enabled: &Enabled, claims: Claims<'_>) -> Result<String, VoiceError> {
        // Header is fixed rather than built from a struct: there is exactly
        // one algorithm this ever uses, and writing it out means it cannot be
        // influenced by anything.
        const HEADER: &str = r#"{"alg":"HS256","typ":"JWT"}"#;
        let payload = serde_json::to_vec(&claims)
            .map_err(|e| VoiceError::Internal(anyhow::Error::from(e)))?;

        let signing_input = format!(
            "{}.{}",
            BASE64URL.encode(HEADER),
            BASE64URL.encode(&payload)
        );

        let mut mac = <Hmac<Sha256>>::new_from_slice(enabled.api_secret.as_bytes())
            .map_err(|e| VoiceError::Internal(anyhow::anyhow!("livekit secret rejected: {e}")))?;
        mac.update(signing_input.as_bytes());
        let signature = BASE64URL.encode(mac.finalize().into_bytes());

        Ok(format!("{signing_input}.{signature}"))
    }
}

/// The LiveKit JWT claim set. Field names are LiveKit's, not ours.
#[derive(Serialize)]
struct Claims<'a> {
    iss: &'a str,
    sub: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    name: Option<&'a str>,
    nbf: u64,
    exp: u64,
    video: VideoGrant,
}

#[derive(Serialize)]
struct VideoGrant {
    room: String,
    #[serde(rename = "roomJoin")]
    room_join: bool,
    #[serde(rename = "roomAdmin")]
    room_admin: bool,
    #[serde(rename = "canSubscribe")]
    can_subscribe: bool,
    #[serde(rename = "canPublish")]
    can_publish: bool,
    #[serde(rename = "canPublishData")]
    can_publish_data: bool,
    #[serde(rename = "canUpdateOwnMetadata")]
    can_update_own_metadata: bool,
}

fn unix_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// The room service address for a client-facing LiveKit URL.
///
/// LiveKit serves signaling and the room service on the same host, so this is
/// a scheme swap rather than a second setting an operator could get wrong.
fn http_url_for(url: &str) -> anyhow::Result<String> {
    let trimmed = url.trim_end_matches('/');
    let swapped = match trimmed.split_once("://") {
        Some(("wss", rest)) => format!("https://{rest}"),
        Some(("ws", rest)) => format!("http://{rest}"),
        Some(("https", _)) | Some(("http", _)) => trimmed.to_owned(),
        _ => anyhow::bail!(
            "SLIMM_LIVEKIT_URL ({url}) must start with wss://, ws://, https:// or http://"
        ),
    };
    Ok(swapped)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn decode_payload(token: &str) -> serde_json::Value {
        let payload = token.split('.').nth(1).expect("a jwt has three parts");
        let bytes = BASE64URL.decode(payload).expect("payload is base64url");
        serde_json::from_slice(&bytes).expect("payload is json")
    }

    fn service() -> VoiceService {
        VoiceService::for_test(
            "wss://livekit.example.com",
            "APIkey",
            "a-secret-at-least-32-chars-long!",
        )
    }

    #[test]
    fn a_disabled_deployment_reports_unavailable_rather_than_failing() {
        let result = VoiceService::disabled().mint(
            ChannelId::generate(),
            UserId::generate(),
            Permissions::ALL,
            "alice",
        );
        assert!(matches!(result, Err(VoiceError::Unavailable)));
        assert!(!VoiceService::disabled().is_enabled());
    }

    #[test]
    fn the_room_is_derived_from_the_channel_and_nothing_else() {
        let channel = ChannelId::generate();
        assert_eq!(room_for_channel(channel), format!("channel-{channel}"));
        // Two channels never share a room, which is what stops a token minted
        // for one from being usable in another.
        assert_ne!(
            room_for_channel(channel),
            room_for_channel(ChannelId::generate())
        );
    }

    #[test]
    fn speak_is_what_decides_whether_a_token_can_publish() {
        let channel = ChannelId::generate();
        let listener = service()
            .mint(
                channel,
                UserId::generate(),
                Permissions::VIEW_CHANNEL.union(Permissions::CONNECT),
                "listener",
            )
            .expect("minted");
        assert!(!listener.can_publish);
        let claims = decode_payload(&listener.token);
        assert_eq!(claims["video"]["canPublish"], false);
        assert_eq!(claims["video"]["canSubscribe"], true);
        assert_eq!(claims["video"]["roomJoin"], true);

        let speaker = service()
            .mint(
                channel,
                UserId::generate(),
                Permissions::VIEW_CHANNEL
                    .union(Permissions::CONNECT)
                    .union(Permissions::SPEAK),
                "speaker",
            )
            .expect("minted");
        assert!(speaker.can_publish);
        assert_eq!(decode_payload(&speaker.token)["video"]["canPublish"], true);
    }

    #[test]
    fn canvas_rights_decide_data_publishing_separately_from_speaking() {
        let token = service()
            .mint(
                ChannelId::generate(),
                UserId::generate(),
                Permissions::CONNECT.union(Permissions::USE_CANVAS),
                "drawer",
            )
            .expect("minted");
        let claims = decode_payload(&token.token);
        assert_eq!(claims["video"]["canPublishData"], true);
        assert_eq!(
            claims["video"]["canPublish"], false,
            "drawing on the canvas must not also grant a microphone"
        );
    }

    #[test]
    fn a_join_token_is_never_a_room_admin_token() {
        let token = service()
            .mint(
                ChannelId::generate(),
                UserId::generate(),
                Permissions::ALL,
                "admin",
            )
            .expect("minted");
        let claims = decode_payload(&token.token);
        assert_eq!(
            claims["video"]["roomAdmin"], false,
            "even an administrator joins as a participant; room admin is the server's own grant"
        );
        assert_eq!(claims["video"]["canUpdateOwnMetadata"], false);
    }

    #[test]
    fn the_token_identifies_the_user_and_expires_soon() {
        let user = UserId::generate();
        let token = service()
            .mint(ChannelId::generate(), user, Permissions::CONNECT, "alice")
            .expect("minted");
        let claims = decode_payload(&token.token);
        assert_eq!(claims["sub"], user.to_string());
        assert_eq!(claims["name"], "alice");
        assert_eq!(claims["iss"], "APIkey");

        let exp = claims["exp"].as_u64().unwrap();
        let nbf = claims["nbf"].as_u64().unwrap();
        assert_eq!(exp - nbf, TOKEN_TTL_SECS);
    }

    #[test]
    fn the_signature_actually_covers_the_payload() {
        let token = service()
            .mint(
                ChannelId::generate(),
                UserId::generate(),
                Permissions::CONNECT,
                "alice",
            )
            .expect("minted");
        let parts: Vec<&str> = token.token.split('.').collect();
        assert_eq!(parts.len(), 3);

        let mut mac = <Hmac<Sha256>>::new_from_slice(b"a-secret-at-least-32-chars-long!").unwrap();
        mac.update(format!("{}.{}", parts[0], parts[1]).as_bytes());
        assert_eq!(BASE64URL.encode(mac.finalize().into_bytes()), parts[2]);
    }

    #[test]
    fn the_room_service_address_is_derived_from_the_client_url() {
        assert_eq!(
            http_url_for("wss://livekit.example.com").unwrap(),
            "https://livekit.example.com"
        );
        assert_eq!(
            http_url_for("ws://10.0.0.100:7880/").unwrap(),
            "http://10.0.0.100:7880"
        );
        assert!(http_url_for("livekit.example.com").is_err());
    }
}
