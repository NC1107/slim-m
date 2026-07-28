// SPDX-License-Identifier: AGPL-3.0-only
//! Unit tests for token minting and signing; split out of `mod.rs` for the
//! line budget. `roster.rs` carries its own tests beside it instead.

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
    // Two channels never share a room, so a token minted for one is useless in another.
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
