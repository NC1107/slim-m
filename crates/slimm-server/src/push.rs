// SPDX-License-Identifier: AGPL-3.0-only
//! Push notification triggering: turns a new message into (at most) one
//! content-free wake per idle recipient, without ever slowing down or failing
//! the send that triggered it.
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

mod envelope;
mod recipients;
mod relay;

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex};

use anyhow::Context;
use url::{Host, Url};

use crate::config::Config;
use crate::ids::{ChannelId, MessageId, Seq, UserId};
use crate::store::{Store, now_ms};

pub use recipients::message_recipients;

/// How long a burst of messages in one channel collapses into a single wake.
/// Leading-edge: the first message in a burst fires immediately and the rest
/// are suppressed until the window elapses, rather than waiting out a
/// trailing quiet period before anyone is notified.
const DEFAULT_DEBOUNCE_WINDOW_MS: i64 = 10_000;

/// How long a device's `foreground` report counts as still current. Past this
/// the app could have backgrounded or been killed without a fresh report (the
/// process was simply suspended, for instance), so treat the state as stale
/// and push anyway rather than risk a silent notification gap.
const FOREGROUND_FRESHNESS_MS: i64 = 60_000;

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
    pub fn notify_message(
        &self,
        store: Store,
        channel_id: ChannelId,
        author_id: UserId,
        message_id: MessageId,
        seq: Seq,
    ) {
        let Some(enabled) = self.inner.clone() else {
            return;
        };
        tokio::spawn(deliver(
            enabled,
            self.debounce.clone(),
            store,
            channel_id,
            author_id,
            message_id,
            seq,
        ));
    }
}

/// The background half of [`PushSender::notify_message`]. Every error path
/// logs and returns rather than propagating: there is no caller left to
/// report to, only the process log.
///
/// The recipient rule lives in [`message_recipients`], including why the author
/// and anybody who blocked them are dropped.
///
/// The debounce is decided once per recipient, even when they have several
/// registered devices, so a second device is never mistaken for a second burst
/// trigger and dropped. A recipient filtered out for being foreground never
/// reaches that decision, so their state can never cost a different recipient
/// (or their own next genuine message) a wake; see the module docs and
/// [`Debounce`].
///
/// A window only stays shut when a recipient was really woken, which means at
/// least one of their devices took the push. Everything else releases it: a
/// batch that failed at the transport level, a recipient whose devices all
/// failed to seal (most likely a corrupt stored key), and the relay's
/// forbidden, error and not_attempted statuses. Treating any of those as
/// success would suppress that recipient's next genuine message, turning a
/// dropped wake into a silently missing notification.
///
/// A status this server does not recognize means the two repos have drifted on
/// the status vocabulary. It is handled as any other inactionable status rather
/// than crashing or misrouting, but logged, since it should never happen
/// against a relay built from the documented contract.
async fn deliver(
    enabled: Arc<Enabled>,
    debounce: Arc<Debounce>,
    store: Store,
    channel_id: ChannelId,
    author_id: UserId,
    message_id: MessageId,
    seq: Seq,
) {
    let recipients = match message_recipients(&store, channel_id, author_id).await {
        Ok(recipients) => recipients,
        Err(err) => {
            tracing::warn!(error = %err, %channel_id, "push: failed to resolve recipients");
            return;
        }
    };
    if recipients.is_empty() {
        return;
    }

    let targets = match store.push_targets(&recipients).await {
        Ok(targets) => targets,
        Err(err) => {
            tracing::warn!(error = %err, %channel_id, "push: failed to load push targets");
            return;
        }
    };

    let now = now_ms();
    let targets: Vec<_> = targets
        .into_iter()
        .filter(|target| !is_foreground_and_recent(target, now))
        .collect();
    if targets.is_empty() {
        return;
    }

    // Once per recipient, not once per device; see the note on this function.
    let mut decisions: HashMap<UserId, Option<i64>> = HashMap::new();
    for target in &targets {
        decisions
            .entry(target.user_id)
            .or_insert_with(|| debounce.try_fire(channel_id, target.user_id));
    }
    let opened: HashMap<UserId, i64> = decisions
        .into_iter()
        .filter_map(|(user_id, fired_at)| fired_at.map(|fired_at| (user_id, fired_at)))
        .collect();
    let targets: Vec<_> = targets
        .into_iter()
        .filter(|target| opened.contains_key(&target.user_id))
        .collect();
    if targets.is_empty() {
        return;
    }

    let messages = envelope::seal_for_message(channel_id, message_id, seq, &targets);

    // Nothing sealed means nothing was attempted, so release; see the note on
    // this function.
    for (&user_id, &fired_at) in &opened {
        if !messages.iter().any(|m| m.user_id == user_id) {
            debounce.release_if_undelivered(channel_id, user_id, fired_at);
        }
    }
    if messages.is_empty() {
        return;
    }

    match relay::send(&enabled.http, &enabled.send_url, &enabled.key, &messages).await {
        Ok(results) => {
            // Only a Delivered device counts as a wake; see the note on this
            // function.
            let mut delivered: HashSet<UserId> = HashSet::new();
            for result in results {
                // The relay echoes back a bare token, so resolve it to the
                // device this batch really sent it to before acting on it.
                let Some(target) = messages.iter().find(|m| m.token == result.token) else {
                    continue;
                };
                match result.parsed_status() {
                    Some(relay::RelayStatus::Delivered) => {
                        delivered.insert(target.user_id);
                    }
                    Some(relay::RelayStatus::Unregistered) => {
                        if let Err(err) = store
                            .clear_push_registration(
                                target.user_id,
                                target.device_id,
                                &result.token,
                            )
                            .await
                        {
                            tracing::warn!(error = %err, "push: failed to clear a dead registration");
                        }
                    }
                    Some(
                        relay::RelayStatus::Forbidden
                        | relay::RelayStatus::Error
                        | relay::RelayStatus::NotAttempted,
                    ) => {}
                    None => {
                        // Inactionable, never misrouted, and logged because it
                        // should never happen; see the note on this function.
                        tracing::warn!(
                            status = %result.status,
                            "push: relay reported a status this server does not recognize"
                        );
                    }
                }
            }
            for (&user_id, &fired_at) in &opened {
                if !delivered.contains(&user_id) {
                    debounce.release_if_undelivered(channel_id, user_id, fired_at);
                }
            }
        }
        Err(err) => {
            tracing::warn!(error = %err, %channel_id, "push: relay send failed");
            // Transport failure notified nobody, so no window may stick; see
            // the note on this function.
            for (&user_id, &fired_at) in &opened {
                debounce.release_if_undelivered(channel_id, user_id, fired_at);
            }
        }
    }
}

/// True if a device's most recent lifecycle report says foreground and that
/// report is still fresh. WebSocket presence is deliberately not consulted
/// here: iOS suspends a socket without closing it, so a connected socket is
/// not evidence the app can show anything right now.
fn is_foreground_and_recent(target: &crate::store::PushTarget, now: i64) -> bool {
    let Some(state) = target.lifecycle_state.as_deref() else {
        return false;
    };
    let Some(reported_at) = target.lifecycle_reported_at else {
        return false;
    };
    state == "foreground" && now - reported_at < FOREGROUND_FRESHNESS_MS
}

/// Collapses a burst of triggers into one per `(channel, recipient)`.
/// Leading-edge: the first trigger after a window last elapsed, or was
/// released (see [`Self::release_if_undelivered`]), opens the window and
/// records `now`; every other trigger for that same pair inside the window is
/// suppressed.
///
/// Keyed on the pair, not the channel alone: one recipient's suppressed
/// window must never silence a different recipient's wake. Debouncing exists
/// to collapse a burst of messages for one person, not to let one recipient's
/// state (or bad luck) silence somebody else's notification.
struct Debounce {
    window_ms: i64,
    last_fired: Mutex<HashMap<(ChannelId, UserId), i64>>,
}

impl Debounce {
    fn new(window_ms: i64) -> Self {
        Self {
            window_ms,
            last_fired: Mutex::new(HashMap::new()),
        }
    }

    /// Attempts to open a window for `(channel_id, user_id)`. `Some(fired_at)`
    /// means this trigger is not suppressed and the caller now owns the
    /// window: if it turns out nobody was actually notified, it must call
    /// [`Self::release_if_undelivered`] with the same `fired_at`, or the next
    /// genuine trigger for this recipient would be wrongly suppressed too.
    /// `None` means a burst is already collapsed into an open window.
    fn try_fire(&self, channel_id: ChannelId, user_id: UserId) -> Option<i64> {
        self.try_fire_at(channel_id, user_id, now_ms())
    }

    /// [`Self::try_fire`] with an explicit clock, for deterministic tests.
    fn try_fire_at(&self, channel_id: ChannelId, user_id: UserId, now: i64) -> Option<i64> {
        let mut last_fired = self.lock();
        let key = (channel_id, user_id);
        match last_fired.get(&key) {
            Some(&last) if now - last < self.window_ms => None,
            _ => {
                last_fired.insert(key, now);
                Some(now)
            }
        }
    }

    /// Releases a window that turned out to deliver nobody anything, so the
    /// next trigger for this recipient is not suppressed by a burst whose
    /// leading edge failed. A no-op if the window has already moved on (it
    /// elapsed naturally and was re-opened by a later, successful trigger)
    /// since `fired_at`, so a late release from a slow delivery task can never
    /// claw back a newer window.
    fn release_if_undelivered(&self, channel_id: ChannelId, user_id: UserId, fired_at: i64) {
        let mut last_fired = self.lock();
        let key = (channel_id, user_id);
        if last_fired.get(&key) == Some(&fired_at) {
            last_fired.remove(&key);
        }
    }

    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<(ChannelId, UserId), i64>> {
        match self.last_fired.lock() {
            Ok(guard) => guard,
            Err(poisoned) => poisoned.into_inner(),
        }
    }
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

    fn user() -> UserId {
        UserId::generate()
    }

    #[test]
    fn debounce_collapses_a_burst_then_reopens() {
        let debounce = Debounce::new(1_000);
        let channel = ChannelId::generate();
        let bob = user();
        assert!(
            debounce.try_fire_at(channel, bob, 0).is_some(),
            "first trigger fires"
        );
        assert!(
            debounce.try_fire_at(channel, bob, 500).is_none(),
            "inside the window is suppressed"
        );
        assert!(
            debounce.try_fire_at(channel, bob, 999).is_none(),
            "still inside the window"
        );
        assert!(
            debounce.try_fire_at(channel, bob, 1_000).is_some(),
            "the window has fully elapsed"
        );
    }

    #[test]
    fn debounce_is_independent_per_channel() {
        let debounce = Debounce::new(1_000);
        let a = ChannelId::generate();
        let b = ChannelId::generate();
        let bob = user();
        assert!(debounce.try_fire_at(a, bob, 0).is_some());
        // A burst in channel a does not suppress channel b.
        assert!(debounce.try_fire_at(b, bob, 0).is_some());
        assert!(debounce.try_fire_at(a, bob, 100).is_none());
    }

    /// Regression: the debounce used to be keyed on channel alone, so a window
    /// opened by one recipient's message silenced every other recipient in the
    /// same channel for the rest of that window.
    #[test]
    fn debounce_is_independent_per_recipient() {
        let debounce = Debounce::new(1_000);
        let channel = ChannelId::generate();
        let bob = user();
        let carol = user();
        assert!(debounce.try_fire_at(channel, bob, 0).is_some());
        assert!(
            debounce.try_fire_at(channel, carol, 50).is_some(),
            "bob's open window must not suppress carol's wake"
        );
        assert!(
            debounce.try_fire_at(channel, bob, 100).is_none(),
            "bob's own burst is still collapsed"
        );
    }

    /// Regression: a leading trigger that ends up delivering nobody anything
    /// (a relay error, or every device filtered out) used to spend the window
    /// regardless, dropping the next message's wake outright instead of merely
    /// collapsing it.
    #[test]
    fn release_if_undelivered_reopens_the_window_immediately() {
        let debounce = Debounce::new(1_000);
        let channel = ChannelId::generate();
        let bob = user();
        let fired_at = debounce
            .try_fire_at(channel, bob, 0)
            .expect("first trigger fires");
        debounce.release_if_undelivered(channel, bob, fired_at);
        assert!(
            debounce.try_fire_at(channel, bob, 1).is_some(),
            "a window that delivered nothing must not suppress the very next trigger"
        );
    }

    #[test]
    fn release_if_undelivered_does_not_clobber_a_newer_window() {
        let debounce = Debounce::new(1_000);
        let channel = ChannelId::generate();
        let bob = user();
        let stale_fired_at = debounce.try_fire_at(channel, bob, 0).unwrap();
        // The window elapses naturally and opens again for a later message.
        assert!(debounce.try_fire_at(channel, bob, 1_000).is_some());
        // A late release from the first (long-finished) delivery task must
        // not tear down the second, newer window.
        debounce.release_if_undelivered(channel, bob, stale_fired_at);
        assert!(
            debounce.try_fire_at(channel, bob, 1_500).is_none(),
            "the newer window must still be in effect"
        );
    }

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
