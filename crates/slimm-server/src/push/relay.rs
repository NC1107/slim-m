// SPDX-License-Identifier: AGPL-3.0-only
//! The HTTP call to the push relay's batch send endpoint, and its wire types.
//!
//! The relay is a separate stateless Go service; this is a thin client for its
//! one endpoint. Everything it carries is already sealed by [`super::envelope`],
//! so nothing here ever sees plaintext content, and nothing here logs a token.

use std::time::Duration;

use serde::{Deserialize, Serialize};

use super::envelope::SealedMessage;

/// Bounded so one slow relay round trip cannot hang the delivery task
/// indefinitely. The message this notifies about is already committed and its
/// HTTP response already sent, so nothing but this background task is waiting.
pub(super) const RELAY_TIMEOUT: Duration = Duration::from_secs(10);

#[derive(Serialize)]
struct SendRequest<'a> {
    messages: Vec<RelayMessage<'a>>,
}

/// Deliberately not `Debug`: `token` and `payload` are exactly what must never
/// be logged.
#[derive(Serialize)]
struct RelayMessage<'a> {
    platform: &'a str,
    token: &'a str,
    kind: &'a str,
    payload: &'a str,
}

#[derive(Deserialize)]
struct SendResponse {
    results: Vec<RelayResult>,
}

/// One token's outcome. Deliberately not `Debug`, so a token cannot end up in
/// a log line by accident.
#[derive(Deserialize)]
pub(super) struct RelayResult {
    pub(super) token: String,
    pub(super) status: String,
}

/// Posts one batch to the relay's `/v1/send` and returns the per-token
/// results. `messages` is expected non-empty; the caller filters out targets
/// with nothing sealed to send before calling this.
pub(super) async fn send(
    http: &reqwest::Client,
    send_url: &str,
    key: &str,
    messages: &[SealedMessage],
) -> anyhow::Result<Vec<RelayResult>> {
    let body = SendRequest {
        messages: messages
            .iter()
            .map(|m| RelayMessage {
                platform: &m.platform,
                token: &m.token,
                kind: m.kind,
                payload: &m.payload,
            })
            .collect(),
    };
    let response = http
        .post(send_url)
        .bearer_auth(key)
        .json(&body)
        .send()
        .await?
        .error_for_status()?;
    let parsed: SendResponse = response.json().await?;
    Ok(parsed.results)
}
