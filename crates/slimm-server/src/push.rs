// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Push notification triggering: turns a new message into (at most) one wake
//! per idle recipient, without ever slowing down or failing the send that
//! triggered it.
//!
//! What that wake carries is [`envelope`]'s subject, and the short version is
//! that the relay can read none of it either way: a device that asked for
//! message content gets a preview sealed to its own key, and every other
//! device gets the same content-free envelope it always did.
//!
//! [`PushSender`] is deliberately a first-class two-state thing rather than an
//! error path. `SLIMM_PUSH_RELAY_URL` and `SLIMM_PUSH_RELAY_KEY` are both
//! optional; a LAN-only or NAT-unreachable self-host has nowhere for a relay
//! to reach it, and that is a fully supported deployment, so an unconfigured
//! sender is a quiet no-op, not a startup failure. When a relay URL is
//! configured, its scheme is checked once here at startup ([`validate_relay_url`]):
//! `http://` leaks every recipient's push token and the relay bearer key in
//! cleartext, so it is refused unless the relay is loopback or private-range,
//! where nothing to leak to ever leaves the LAN.
//!
//! Triggering reads the client-reported lifecycle state, never raw WebSocket
//! presence: iOS suspends a socket without closing it, so a live connection is
//! not proof the app can show anything. A short debounce, keyed per
//! `(channel, recipient)` and evaluated only after lifecycle filtering,
//! collapses a burst of messages to one recipient into one wake instead of one
//! push per message, without one recipient's suppressed window ever silencing
//! a different recipient. A window that turns out to have delivered nobody
//! anything (a relay error, or a stored key too corrupt to seal to) is
//! released rather than left spent, so it collapses a burst instead of
//! dropping the next message's wake outright; see [`Debounce`].
//!
//! [`PushSender::notify_message`] is called synchronously from the message
//! send handler but does no I/O itself: it makes a cheap in-memory decision
//! (is push even enabled?) and, if so, hands everything else, including the
//! debounce, to a detached [`tokio::spawn`]ed task. The message is already
//! committed and its response already on the way back to the caller, so
//! nothing here can turn a successful send into an error, and nothing here can
//! make it slower.

mod call_ring;
mod debounce;
mod deliver;
mod envelope;
mod recipients;
mod relay;

use std::sync::Arc;

use anyhow::Context;
use url::{Host, Url};

use crate::config::Config;
use crate::ids::{CallRingId, ChannelId, MessageId, Seq, UserId};
use crate::presence::PresenceTracker;
use crate::store::Store;

use debounce::Debounce;

pub use recipients::message_recipients;

/// How long a burst of messages in one channel collapses into a single wake.
/// Leading-edge: the first message in a burst fires immediately and the rest
/// are suppressed until the window elapses, rather than waiting out a
/// trailing quiet period before anyone is notified.
const DEFAULT_DEBOUNCE_WINDOW_MS: i64 = 10_000;

/// Triggers push for new messages. Cheap to clone (an `Option<Arc<_>>` plus an
/// `Arc<Debounce>`), so it lives directly on [`crate::http::AppState`].
#[derive(Clone)]
pub struct PushSender {
    inner: Option<Arc<Enabled>>,
    debounce: Arc<Debounce>,
}

struct Enabled {
    http: reqwest::Client,
    send_url: String,
    key: String,
}

impl PushSender {
    /// Builds a sender from the process config. Disabled, quietly and
    /// permanently for this process's life, unless both the relay URL and key
    /// are set; logs that decision once, here, at startup. Fails if a relay
    /// URL is set but its scheme is not safe to use (see
    /// [`validate_relay_url`]), so a misconfigured deployment refuses to start
    /// rather than leaking silently the first time it sends a push.
    pub fn new(config: &Config) -> anyhow::Result<Self> {
        Self::with_debounce_window_ms(config, DEFAULT_DEBOUNCE_WINDOW_MS)
    }

    /// [`Self::new`] with an explicit debounce window, so tests can exercise
    /// collapsing (and its expiry) without waiting out the real window.
    ///
    /// Redirects are refused rather than followed. reqwest strips sensitive
    /// headers across a redirect only when the host or port changes, comparing
    /// neither the scheme, so an https to http downgrade back to the same host
    /// would carry the relay bearer key and every device push token in it. The
    /// relay is a known endpoint we configure, so it has no business
    /// redirecting.
    pub fn with_debounce_window_ms(config: &Config, window_ms: i64) -> anyhow::Result<Self> {
        let inner = match (&config.push_relay_url, &config.push_relay_key) {
            (Some(url), Some(key)) => {
                validate_relay_url(url)?;
                // Redirects refused, not followed; see the note on this
                // function.
                let http = reqwest::Client::builder()
                    .timeout(relay::RELAY_TIMEOUT)
                    .redirect(reqwest::redirect::Policy::none())
                    .build()
                    .expect("building the push relay HTTP client");
                Some(Arc::new(Enabled {
                    http,
                    send_url: format!("{}/v1/send", url.trim_end_matches('/')),
                    key: key.clone(),
                }))
            }
            _ => {
                tracing::info!(
                    "SLIMM_PUSH_RELAY_URL / SLIMM_PUSH_RELAY_KEY not set; push notifications are disabled"
                );
                None
            }
        };
        Ok(Self {
            inner,
            debounce: Arc::new(Debounce::new(window_ms)),
        })
    }

    /// A sender that never reaches a relay. Distinct from a misconfigured
    /// [`Self::new`] only in that it never logs: it is the explicit choice a
    /// caller (mainly tests) makes, not the outcome of missing config.
    pub fn disabled() -> Self {
        Self {
            inner: None,
            debounce: Arc::new(Debounce::new(DEFAULT_DEBOUNCE_WINDOW_MS)),
        }
    }

    /// Whether this sender will actually reach a relay.
    pub fn is_enabled(&self) -> bool {
        self.inner.is_some()
    }

    /// Considers pushing a wake for a message that was just committed.
    ///
    /// Synchronous and cheap: a disabled sender returns immediately without
    /// touching the database or the network. Otherwise the recipient lookup,
    /// lifecycle gating, per-recipient debounce, sealing, and relay call all
    /// happen in a detached background task, so this never blocks or fails
    /// the caller. The debounce is not decided here: it needs to know who the
    /// recipients are first, so it is evaluated inside that task instead (see
    /// [`Debounce`]).
    pub fn notify_message(&self, store: Store, sent: SentMessage) {
        let Some(enabled) = self.inner.clone() else {
            return;
        };
        tokio::spawn(deliver::deliver(
            enabled,
            self.debounce.clone(),
            store,
            sent,
        ));
    }

    /// Considers pushing a wake for a DM call ring that was just started.
    ///
    /// The same synchronous-and-cheap shape [`Self::notify_message`] already
    /// has: a disabled sender returns immediately, and everything else -
    /// the preference check, the lookup, sealing, and the relay call - runs
    /// in a detached background task so this never blocks the `ring` route's
    /// own response. No debounce: see `call_ring`'s own module doc for why a
    /// ring never needs one.
    pub fn notify_call_ring(
        &self,
        store: Store,
        channel_id: ChannelId,
        ring_id: CallRingId,
        caller_id: UserId,
        callee_id: UserId,
    ) {
        let Some(enabled) = self.inner.clone() else {
            return;
        };
        tokio::spawn(call_ring::deliver(
            enabled, store, channel_id, ring_id, caller_id, callee_id,
        ));
    }
}

/// What [`PushSender::notify_message`] needs to know about a message that was
/// just committed, bundled rather than five positional arguments.
///
/// `content` is read to resolve `@`-mentions for [`message_recipients`]'s
/// thread narrowing, and, for a device that asked for it, to build the preview
/// sealed inside that device's own envelope. It is never put on the wire in a
/// form the relay can read: a preview only ever exists inside the sealed box,
/// which is why this is a per-device choice at all rather than a deployment
/// one. See [`envelope`]'s module docs.
pub struct SentMessage {
    pub channel_id: ChannelId,
    pub author_id: UserId,
    pub message_id: MessageId,
    pub seq: Seq,
    pub content: String,
    pub presence: PresenceTracker,
}

/// Refuses a push relay URL that would send every recipient's APNs/FCM token
/// and the relay bearer key across the network in cleartext. `https://` is
/// always fine; `http://` is allowed only for a loopback or private-range
/// host, where a LAN-local relay with nowhere to terminate TLS is a
/// legitimate deployment and nothing sent to it leaves the LAN. Checked once
/// here at startup, so a bad scheme fails loudly at boot rather than leaking
/// silently the first time a push is sent.
fn validate_relay_url(raw: &str) -> anyhow::Result<()> {
    let url = Url::parse(raw)
        .with_context(|| format!("SLIMM_PUSH_RELAY_URL is not a valid URL: {raw:?}"))?;
    match url.scheme() {
        "https" => Ok(()),
        "http" if is_local_relay_host(url.host()) => Ok(()),
        "http" => anyhow::bail!(
            "SLIMM_PUSH_RELAY_URL ({raw}) uses http:// for a non-local relay host; \
             use https://, or point it at a loopback or private-range address"
        ),
        other => anyhow::bail!(
            "SLIMM_PUSH_RELAY_URL ({raw}) has an unsupported scheme {other:?}; \
             it must be https:// (or http:// only for a loopback/private-range relay)"
        ),
    }
}

/// Whether a relay host is loopback or private-range: the cases where an
/// unencrypted LAN-local relay is legitimate rather than a leak. Matches the
/// boundaries RFC 1918 and RFC 4193 define (so, for example, 172.16.0.0/12 is
/// private but 172.32.0.0 is not, and `localhost` counts without a DNS
/// lookup).
fn is_local_relay_host(host: Option<Host<&str>>) -> bool {
    match host {
        Some(Host::Domain(domain)) => domain.eq_ignore_ascii_case("localhost"),
        Some(Host::Ipv4(addr)) => addr.is_loopback() || addr.is_private(),
        Some(Host::Ipv6(addr)) => addr.is_loopback() || addr.is_unique_local(),
        None => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn disabled_sender_reports_disabled() {
        assert!(!PushSender::disabled().is_enabled());
    }

    #[test]
    fn relay_url_requires_https_for_a_public_host() {
        assert!(validate_relay_url("https://relay.example.com").is_ok());
        assert!(validate_relay_url("http://relay.example.com").is_err());
        assert!(validate_relay_url("ftp://relay.example.com").is_err());
        assert!(validate_relay_url("not a url").is_err());
    }

    #[test]
    fn relay_url_allows_http_for_loopback_and_private_ranges() {
        for ok in [
            "http://127.0.0.1:9000",
            "http://localhost:9000",
            "http://LOCALHOST:9000",
            "http://10.1.2.3",
            "http://172.16.0.1",
            "http://172.31.255.255",
            "http://192.168.1.1",
            "http://[::1]:9000",
        ] {
            assert!(
                validate_relay_url(ok).is_ok(),
                "{ok} should be allowed over http"
            );
        }
        // 172.16.0.0/12 (RFC 1918) ends at 172.31.255.255; 172.32.0.0 is a
        // routable public address and must not be treated as LAN-local.
        assert!(
            validate_relay_url("http://172.32.0.1").is_err(),
            "172.32 is outside the private range and must require https"
        );
    }

    #[test]
    fn with_debounce_window_ms_rejects_a_cleartext_public_relay() {
        let config = Config {
            port: 0,
            database_path: String::new(),
            hash_concurrency: 1,
            push_relay_url: Some("http://relay.example.com".to_owned()),
            push_relay_key: Some("key".to_owned()),
            ..Config::default()
        };
        assert!(
            PushSender::with_debounce_window_ms(&config, 1_000).is_err(),
            "a cleartext relay over the public internet must fail loudly at startup"
        );
    }
}
