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

use std::time::{Duration, Instant};

use axum::Router;
use axum::extract::State;
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use futures_util::stream::{SplitSink, SplitStream};
use futures_util::{SinkExt, StreamExt};
use tokio::sync::OwnedSemaphorePermit;
use tokio::sync::broadcast::error::RecvError;

use super::AppState;
use super::PROTOCOL_VERSION;
use super::channels::ChannelDto;
use super::messages::{AttachmentDto, MessageDto};
use crate::hub::{Event, Hub};
use crate::permissions::Permissions;
use crate::store::{SessionContext, Store};
use frames::{ClientFrame, PollOptionCountDto, ReactionCountDto, ServerFrame};
use view_cache::ViewCache;

mod frames;
mod signals;
mod view_cache;

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

// --- Connection ---

async fn serve(socket: WebSocket, state: AppState, _permit: OwnedSemaphorePermit) {
    let (mut sink, mut stream) = socket.split();

    let ctx = match authenticate(&mut sink, &mut stream, &state).await {
        Some(ctx) => ctx,
        None => return,
    };

    // Subscribe before acking the hello, so an event published during the
    // handshake is buffered rather than missed.
    let mut events = state.hub.subscribe();

    // Per connection, and dropped with it; see `view_cache`.
    let mut view_cache = ViewCache::new();

    // Guarantees the matching disconnect however this function returns; see
    // `signals::PresenceGuard`.
    let _presence_guard = signals::PresenceGuard::connect(state.hub.clone(), ctx.user_id);

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
                        match serde_json::from_str::<ClientFrame>(text.as_str()) {
                            Ok(ClientFrame::Ping) => {
                                if send_frame(&mut sink, &ServerFrame::Pong).await.is_err() {
                                    break;
                                }
                            }
                            Ok(ClientFrame::Typing { channel_id }) => {
                                signals::handle_typing(
                                    &state.store,
                                    &state.hub,
                                    &state.limiter,
                                    &ctx,
                                    &channel_id,
                                )
                                .await;
                            }
                            // A second hello or anything unparseable is not
                            // worth tearing the connection down over.
                            Ok(ClientFrame::Hello { .. }) | Err(_) => {}
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
                        if let Some(frame) =
                            authorize(&state.store, &state.hub, &ctx, &mut view_cache, event).await
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
///
/// Presence is handled up front rather than folded into the channel-scoped
/// match: it has no channel to check view permission against (it is
/// deployment-wide, like the member list) and needs the receiving connection's
/// own user id to resolve the right answer for it.
async fn authorize(
    store: &Store,
    hub: &Hub,
    ctx: &SessionContext,
    view_cache: &mut ViewCache,
    event: Event,
) -> Option<ServerFrame> {
    // Ahead of the channel-scoped match below; see the note on this function.
    if let Event::PresenceChanged(target_id) = event {
        // A gone account and a store blip both mean silence here, unlike below.
        let Ok(Some(status)) = signals::presence_status(store, hub, ctx.user_id, target_id).await
        else {
            return None;
        };
        return Some(ServerFrame::PresenceChanged {
            user_id: target_id.to_string(),
            status: status.as_str().to_owned(),
        });
    }
    // Deployment-wide like presence, but with nothing per-viewer to resolve.
    match event {
        Event::MemberTimeoutChanged { user_id, until } => {
            return Some(ServerFrame::MemberTimeoutChanged {
                user_id: user_id.to_string(),
                until,
            });
        }
        Event::MemberRemoved(user_id) => {
            return Some(ServerFrame::MemberRemoved {
                user_id: user_id.to_string(),
            });
        }
        Event::RoleChanged { role_id } => {
            return Some(ServerFrame::RoleChanged {
                role_id: role_id.to_string(),
            });
        }
        Event::MemberRoleChanged { user_id, role_id } => {
            return Some(ServerFrame::MemberRoleChanged {
                user_id: user_id.to_string(),
                role_id: role_id.to_string(),
            });
        }
        _ => {}
    }

    // Special-cased; see `Event::ChannelDeleted`'s doc comment for why.
    if let Event::ChannelDeleted { channel_id } = event {
        let viewed = store
            .viewed_channel_before_delete(ctx.user_id, channel_id)
            .await
            .unwrap_or(false);
        return viewed.then(|| ServerFrame::ChannelDeleted {
            channel_id: channel_id.to_string(),
        });
    }

    let channel_id = match &event {
        Event::MessageCreated { message, .. } | Event::MessageEdited(message) => message.channel_id,
        Event::MessageDeleted { channel_id, .. } => *channel_id,
        Event::ReactionsChanged { channel_id, .. } => *channel_id,
        Event::MessagePinned { channel_id, .. } => *channel_id,
        Event::MessageUnpinned { channel_id, .. } => *channel_id,
        Event::PollVoted { channel_id, .. } => *channel_id,
        Event::TypingStarted { channel_id, .. } | Event::TypingStopped { channel_id, .. } => {
            *channel_id
        }
        Event::ChannelCreated(channel) | Event::ChannelUpdated(channel) => channel.id,
        Event::OverwriteChanged { channel_id, .. } => *channel_id,
        // Control events are handled in the loop; the rest already returned above.
        Event::SessionRevoked(_)
        | Event::PresenceChanged(_)
        | Event::MemberTimeoutChanged { .. }
        | Event::MemberRemoved(_)
        | Event::RoleChanged { .. }
        | Event::MemberRoleChanged { .. }
        | Event::ChannelDeleted { .. } => return None,
    };
    // The one event whose subject may have just lost this very view.
    let held_it_before = matches!(
        &event,
        Event::OverwriteChanged { previously_visible_to, .. }
            if previously_visible_to.contains(&ctx.user_id)
    );
    // Read before the query, never after; see `ViewCache::insert`.
    let epoch = hub.permissions_epoch();
    let visible = match view_cache.get(channel_id, Instant::now(), epoch) {
        Some(cached) => cached,
        None => match store
            .has_permission(ctx.user_id, channel_id, Permissions::VIEW_CHANNEL)
            .await
        {
            Ok(answer) => {
                view_cache.insert(channel_id, answer, Instant::now(), epoch);
                answer
            }
            // Fails closed for this event only; a blip must not be remembered.
            Err(_) => false,
        },
    };
    if !visible && !held_it_before {
        return None;
    }

    // Typing carries the typist's id to everyone in the channel, so it is a
    // second way to learn someone is online. Appear-offline is enforced at
    // one choke point for exactly this reason, and a typing frame bypassed it:
    // a hidden user's keystrokes announced them. Dropped here, per viewer,
    // through the same function every other presence surface uses.
    //
    // Unlike the `PresenceChanged` branch above, this one must fail closed on
    // a store blip rather than let it through: withholding a status change
    // just loses an update, but withholding this gate leaks one. So only a
    // confirmed non-offline status clears it; `Ok(None)` (account gone) and
    // `Err` (could not tell) both drop the frame, same as a real `Offline`.
    if let Event::TypingStarted { user_id, .. } | Event::TypingStopped { user_id, .. } = event {
        let confirmed_visible = matches!(
            signals::presence_status(store, hub, ctx.user_id, user_id).await,
            Ok(Some(status)) if status != crate::presence::Status::Offline
        );
        if !confirmed_visible {
            return None;
        }
    }

    Some(match event {
        Event::MessageCreated {
            message,
            attachments,
        } => {
            let channel_id = message.channel_id.to_string();
            let seq = message.seq.0;
            let mut dto = MessageDto::from(message);
            dto.attachments = attachments.into_iter().map(AttachmentDto::from).collect();
            ServerFrame::MessageCreated {
                channel_id,
                seq,
                message: dto,
            }
        }
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
        } => ServerFrame::ReactionsChanged {
            channel_id: channel_id.to_string(),
            message_id: message_id.to_string(),
            // Per viewer: see the event's own doc comment for why.
            reactions: store
                .reactions_for_message(message_id, ctx.user_id)
                .await
                .ok()?
                .into_iter()
                .map(|summary| ReactionCountDto {
                    emoji: summary.emoji,
                    count: summary.count,
                })
                .collect(),
        },
        Event::MessagePinned {
            channel_id,
            message_id,
            pinned_by,
            pinned_at,
        } => ServerFrame::MessagePinned {
            channel_id: channel_id.to_string(),
            message_id: message_id.to_string(),
            pinned_by: pinned_by.map(|id| id.to_string()),
            pinned_at,
        },
        Event::MessageUnpinned {
            channel_id,
            message_id,
        } => ServerFrame::MessageUnpinned {
            channel_id: channel_id.to_string(),
            message_id: message_id.to_string(),
        },
        Event::PollVoted {
            channel_id,
            message_id,
            options,
        } => ServerFrame::PollVoted {
            channel_id: channel_id.to_string(),
            message_id: message_id.to_string(),
            options: options
                .into_iter()
                .map(|(position, votes)| PollOptionCountDto { position, votes })
                .collect(),
        },
        Event::TypingStarted {
            channel_id,
            user_id,
        } => ServerFrame::TypingStarted {
            channel_id: channel_id.to_string(),
            user_id: user_id.to_string(),
        },
        Event::TypingStopped {
            channel_id,
            user_id,
        } => ServerFrame::TypingStopped {
            channel_id: channel_id.to_string(),
            user_id: user_id.to_string(),
        },
        Event::ChannelCreated(channel) => ServerFrame::ChannelCreated {
            channel: ChannelDto::from(channel),
        },
        Event::ChannelUpdated(channel) => ServerFrame::ChannelUpdated {
            channel: ChannelDto::from(channel),
        },
        Event::OverwriteChanged { channel_id, .. } => ServerFrame::OverwriteChanged {
            channel_id: channel_id.to_string(),
        },
        // The deployment-wide and channel-deletion cases already returned above.
        Event::SessionRevoked(_)
        | Event::PresenceChanged(_)
        | Event::MemberTimeoutChanged { .. }
        | Event::MemberRemoved(_)
        | Event::RoleChanged { .. }
        | Event::MemberRoleChanged { .. }
        | Event::ChannelDeleted { .. } => return None,
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
