// SPDX-License-Identifier: AGPL-3.0-only
//! The WebSocket surface: connect, authenticate, negotiate, and fan out events.
//!
//! A client connects to `/ws`, then sends a `hello` frame carrying a single-use
//! connect ticket (minted over REST from its session) and the protocol version
//! it speaks. The server redeems the ticket, confirms the version, and replies
//! with its own `hello`. From then on the connection is a one-way fan-out of
//! events the user is allowed to see, plus a `ping`/`pong` keepalive.
//!
//! Delivery is authorized per event: a `message.created` reaches a connection
//! only if that user can view the channel it happened in, so the socket never
//! leaks a channel the caller could not read over REST. If the connection falls
//! behind the broadcast buffer it is closed and the client resyncs over REST.

use std::time::Duration;

use axum::Router;
use axum::extract::State;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use futures_util::stream::{SplitSink, SplitStream};
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tokio::sync::OwnedSemaphorePermit;
use tokio::sync::broadcast::error::RecvError;

use super::AppState;
use super::PROTOCOL_VERSION;
use super::messages::MessageDto;
use crate::hub::Event;
use crate::permissions::Permissions;
use crate::store::{SessionContext, Store};

/// How long a freshly connected socket has to send its `hello` before it is
/// dropped, so unauthenticated sockets cannot linger.
const AUTH_DEADLINE: Duration = Duration::from_secs(10);

/// How long a single send may block before the peer is treated as dead. Without
/// this a peer that completes the handshake and then stops reading could wedge
/// its connection task indefinitely.
const WRITE_TIMEOUT: Duration = Duration::from_secs(10);

/// Legitimate frames are tiny JSON; cap message and frame size well below the
/// library defaults so a client cannot force a large buffer.
const MAX_FRAME_BYTES: usize = 4 * 1024;

type Sink = SplitSink<WebSocket, Message>;
type Stream = SplitStream<WebSocket>;

/// The WebSocket route, mounted by [`super::router`].
pub fn routes() -> Router<AppState> {
    Router::new().route("/ws", get(connect))
}

async fn connect(ws: WebSocketUpgrade, State(state): State<AppState>) -> Response {
    // Claim a connection slot before upgrading, so a flood cannot open unbounded
    // sockets. The permit is held for the connection's whole life.
    let Some(permit) = state.hub.try_connect() else {
        return (StatusCode::SERVICE_UNAVAILABLE, "too many connections").into_response();
    };
    ws.max_message_size(MAX_FRAME_BYTES)
        .max_frame_size(MAX_FRAME_BYTES)
        .on_upgrade(move |socket| serve(socket, state, permit))
}

// ---------------------------------------------------------------------------
// Envelope
// ---------------------------------------------------------------------------

#[derive(Serialize)]
#[serde(tag = "type")]
enum ServerFrame {
    #[serde(rename = "hello")]
    Hello { protocol: u32 },
    #[serde(rename = "message.created")]
    MessageCreated {
        channel_id: String,
        seq: i64,
        message: MessageDto,
    },
    #[serde(rename = "message.edited")]
    MessageEdited {
        channel_id: String,
        seq: i64,
        message: MessageDto,
    },
    #[serde(rename = "message.deleted")]
    MessageDeleted {
        channel_id: String,
        message_id: String,
    },
    #[serde(rename = "reactions.changed")]
    ReactionsChanged {
        channel_id: String,
        message_id: String,
        reactions: Vec<ReactionCountDto>,
    },
    #[serde(rename = "pong")]
    Pong,
    #[serde(rename = "error")]
    Error { message: String },
}

/// One emoji and how many people used it. Public counts only: what the asking
/// user reacted with is per viewer and never broadcast.
#[derive(Serialize)]
pub(crate) struct ReactionCountDto {
    emoji: String,
    count: i64,
}

#[derive(Deserialize)]
#[serde(tag = "type")]
enum ClientFrame {
    #[serde(rename = "hello")]
    Hello { ticket: String, protocol: u32 },
    #[serde(rename = "ping")]
    Ping,
}

// ---------------------------------------------------------------------------
// Connection
// ---------------------------------------------------------------------------

async fn serve(socket: WebSocket, state: AppState, _permit: OwnedSemaphorePermit) {
    let (mut sink, mut stream) = socket.split();

    let ctx = match authenticate(&mut sink, &mut stream, &state).await {
        Some(ctx) => ctx,
        None => return,
    };

    // Subscribe before acking the hello, so an event published during the
    // handshake is buffered rather than missed.
    let mut events = state.hub.subscribe();
    if send_frame(
        &mut sink,
        &ServerFrame::Hello {
            protocol: PROTOCOL_VERSION,
        },
    )
    .await
    .is_err()
    {
        return;
    }

    loop {
        tokio::select! {
            incoming = stream.next() => {
                match incoming {
                    Some(Ok(Message::Text(text))) => {
                        if let Ok(ClientFrame::Ping) = serde_json::from_str::<ClientFrame>(text.as_str())
                            && send_frame(&mut sink, &ServerFrame::Pong).await.is_err()
                        {
                            break;
                        }
                    }
                    Some(Ok(Message::Close(_))) | None => break,
                    Some(Err(_)) => break,
                    // Other frames (binary, ping, pong) are ignored; axum answers
                    // protocol-level pings itself.
                    Some(Ok(_)) => {}
                }
            }
            event = events.recv() => {
                match event {
                    // Our own session was revoked: close the socket at once.
                    Ok(Event::SessionRevoked(session_id)) => {
                        if session_id == ctx.session_id {
                            break;
                        }
                    }
                    Ok(event) => {
                        if let Some(frame) = authorize(&state.store, &ctx, event).await
                            && send_frame(&mut sink, &frame).await.is_err()
                        {
                            break;
                        }
                    }
                    Err(RecvError::Lagged(_)) => {
                        let _ = send_frame(
                            &mut sink,
                            &ServerFrame::Error { message: "resync".to_owned() },
                        )
                        .await;
                        break;
                    }
                    Err(RecvError::Closed) => break,
                }
            }
        }
    }
}

/// Reads and validates the opening `hello`, returning the session it authorizes.
/// On any failure it sends an error frame and returns `None`; the caller closes.
async fn authenticate(
    sink: &mut Sink,
    stream: &mut Stream,
    state: &AppState,
) -> Option<SessionContext> {
    let opening = tokio::time::timeout(AUTH_DEADLINE, stream.next()).await;
    let text = match opening {
        Ok(Some(Ok(Message::Text(text)))) => text,
        _ => return reject(sink, "expected a hello frame").await,
    };

    let (ticket, protocol) = match serde_json::from_str::<ClientFrame>(text.as_str()) {
        Ok(ClientFrame::Hello { ticket, protocol }) => (ticket, protocol),
        _ => return reject(sink, "expected a hello frame").await,
    };
    if protocol != PROTOCOL_VERSION {
        return reject(sink, "unsupported protocol version").await;
    }

    match state.store.redeem_ws_ticket(&ticket).await {
        Ok(Some(ctx)) => Some(ctx),
        _ => reject(sink, "invalid ticket").await,
    }
}

/// Filters an event down to a wire frame, or `None` if this user may not see it.
/// A permission-check error fails closed (no delivery).
async fn authorize(store: &Store, ctx: &SessionContext, event: Event) -> Option<ServerFrame> {
    let channel_id = match &event {
        Event::MessageCreated(message) | Event::MessageEdited(message) => message.channel_id,
        Event::MessageDeleted { channel_id, .. } => *channel_id,
        Event::ReactionsChanged { channel_id, .. } => *channel_id,
        // Control events are handled in the loop, never here.
        Event::SessionRevoked(_) => return None,
    };
    let visible = store
        .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
        .await
        .unwrap_or(false);
    if !visible {
        return None;
    }

    Some(match event {
        Event::MessageCreated(message) => ServerFrame::MessageCreated {
            channel_id: message.channel_id.to_string(),
            seq: message.seq.0,
            message: MessageDto::from(message),
        },
        Event::MessageEdited(message) => ServerFrame::MessageEdited {
            channel_id: message.channel_id.to_string(),
            seq: message.seq.0,
            message: MessageDto::from(message),
        },
        Event::MessageDeleted {
            channel_id,
            message_id,
        } => ServerFrame::MessageDeleted {
            channel_id: channel_id.to_string(),
            message_id: message_id.to_string(),
        },
        Event::ReactionsChanged {
            channel_id,
            message_id,
            reactions,
        } => ServerFrame::ReactionsChanged {
            channel_id: channel_id.to_string(),
            message_id: message_id.to_string(),
            reactions: reactions
                .into_iter()
                .map(|(emoji, count)| ReactionCountDto { emoji, count })
                .collect(),
        },
        Event::SessionRevoked(_) => return None,
    })
}

async fn send_frame(sink: &mut Sink, frame: &ServerFrame) -> Result<(), ()> {
    let text = serde_json::to_string(frame).map_err(|_| ())?;
    // A send that does not complete within the deadline means the peer stopped
    // reading; treat it like any other send failure and close the connection.
    match tokio::time::timeout(WRITE_TIMEOUT, sink.send(Message::Text(text.into()))).await {
        Ok(Ok(())) => Ok(()),
        _ => Err(()),
    }
}

/// Sends a final error frame and resolves to `None`.
async fn reject(sink: &mut Sink, message: &str) -> Option<SessionContext> {
    let _ = send_frame(
        sink,
        &ServerFrame::Error {
            message: message.to_owned(),
        },
    )
    .await;
    None
}
