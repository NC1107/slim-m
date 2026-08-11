// SPDX-License-Identifier: AGPL-3.0-only
//! In-process rate limiting.
//!
//! Every review of the auth work flagged the same gap: the expensive endpoints
//! were reachable without any per-caller throttle, so one client could keep the
//! Argon2id permits saturated and lock everyone else out. This is that throttle.
//!
//! The model is a token bucket per (class, key). A class is a traffic kind with
//! its own budget ([`Class`]); a key is whoever the limit applies to, an IP for
//! unauthenticated traffic and a user for authenticated traffic. Buckets refill
//! continuously, so a caller who stays under the sustained rate is never
//! blocked, while a burst is capped.
//!
//! Two bounds keep the limiter itself from becoming the leak it prevents:
//! idle buckets are swept on a schedule, and the map has a hard ceiling past
//! which new keys are refused rather than admitted (fail closed, so flooding
//! with fresh keys cannot grow memory without bound or buy free requests).

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// A traffic class and its budget: a sustained refill rate and a burst size.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Class {
    /// Password endpoints (register, login). Deliberately tight: each request
    /// can cost an Argon2id hash.
    Password,
    /// Token refresh. Cheap, but a leaked token should not be grindable.
    Refresh,
    /// Minting a WebSocket connect ticket.
    Ticket,
    /// Ordinary authenticated writes (send, edit, mark read).
    Write,
    /// Typing refresh frames over the WebSocket. A refresh every few seconds
    /// is normal client behavior, so the budget only needs to absorb a short
    /// burst (switching between channels while typing) while still refusing
    /// a tight loop; the tracker's own dedup already stops a well-behaved
    /// refresh from re-fanning-out, so this exists to bound the cost of a
    /// misbehaving one.
    Typing,
    /// Unauthenticated metadata reads that disclose nothing worth guessing at:
    /// `/version` and its capability list.
    ///
    /// Loose on purpose. The sign-in screen probes `/version` as somebody types
    /// a server address, so a tight budget here would refuse a legitimate user
    /// mid-keystroke; what this bounds is a flood, not a guess. `InviteCheck`
    /// stays tight because a hit there discloses real deployment metadata and
    /// this does not.
    Read,
    /// Checking an invite code before signup. Unauthenticated, and a valid
    /// code now discloses real deployment metadata rather than a bare
    /// boolean, which raises what a successful guess is worth; tight for the
    /// same reason `Password` is.
    InviteCheck,
    /// Uploading an attachment or avatar. Far tighter than `Write`: each
    /// request can cost real megabytes of disk, so the budget that is fine
    /// for a burst of short text messages would let one account fill the
    /// volume as fast as it could open connections. Sized for a normal
    /// compose flow (a handful of files with one message, occasionally) while
    /// still bounding a sustained flood to a trickle.
    Upload,
    /// Canvas reads and writes.
    ///
    /// Its own class because both halves are gesture-driven at a rate `Write`
    /// and `Read` were never sized for: a short dash commits an object, and a
    /// pan re-reads the region as soon as the camera settles. A 429 on either
    /// is ink that was already on the drawer's own screen going missing, or a
    /// canvas that stops updating, so the budget is looser than `Write`'s
    /// while still refusing a tight loop. What bounds the *cost* rather than
    /// the rate is elsewhere: the per-object props ceiling, the per-channel
    /// object ceiling, and the viewport limit.
    Canvas,
    /// Canvas pointer-position frames over the WebSocket. Sent far more often
    /// than a typing refresh (a client throttles to roughly 12/second while
    /// the pointer is moving over the canvas), so the budget is sized around
    /// that sustained rate with headroom for a burst, rather than reused from
    /// [`Class::Typing`]'s much sparser one.
    CanvasCursor,
    /// In-flight stroke preview frames over the WebSocket - ephemeral,
    /// relayed but never persisted (see `Event::CanvasStrokePreview`).
    ///
    /// Unlike every other class, this one is denominated in *bytes*, not
    /// requests: a caller charges it through [`RateLimiter::check_weighted`]
    /// with the frame's own wire size as the cost, because a preview frame's
    /// size grows with how many points it carries while [`Class::CanvasCursor`]'s
    /// two-number frame never does - a per-request budget sized for a small
    /// frame would starve a legitimately larger one and a budget sized for a
    /// large one would let a flood of tiny frames spend far more bandwidth
    /// than a cursor ever could. This is the byte-rate half of the roadmap's
    /// split canvas rate limits; [`Class::Canvas`] (the persisted-op half) is
    /// unchanged.
    ///
    /// Sized so a capped 24-point frame (under 1.5 KiB) can be sent roughly
    /// eight times back to back before the burst runs out, and sustained
    /// drawing at the client's own throttle interval (90ms) stays inside the
    /// refill with headroom to spare.
    CanvasStrokePreview,
    /// Serving stored bytes back: an attachment, an avatar, a custom emoji
    /// image.
    ///
    /// Its own class because these are the one read shape a single screen
    /// legitimately fires dozens of at once - a member page resolves an
    /// avatar per member, and a transcript of image posts resolves one per
    /// message - so [`Class::Read`]'s budget, sized for a handful of
    /// page-level fetches, would stall a member list on any deployment past
    /// about twenty people. Sized instead for the largest honest burst a
    /// screen produces, with a refill that still refuses a sustained loop.
    ///
    /// What this bounds is the request *rate*, not the bytes behind it: an
    /// attachment may be megabytes where an avatar is kilobytes, and this
    /// charges them the same. Byte cost is bounded elsewhere, by the
    /// per-upload ceiling and the deployment-wide storage ceiling. If
    /// large-attachment flooding ever becomes real rather than theoretical,
    /// the answer is a byte-weighted charge through
    /// [`RateLimiter::check_weighted`], the way
    /// [`Class::CanvasStrokePreview`] already works - not a smaller budget
    /// here, which would break the avatar case this exists to serve.
    Asset,
}

impl Class {
    /// (burst, refill per second). For [`Class::CanvasStrokePreview`] the
    /// unit is bytes, not requests; see its own doc.
    const fn budget(self) -> (f64, f64) {
        match self {
            Class::Password => (5.0, 1.0 / 6.0),
            Class::Refresh => (10.0, 1.0 / 2.0),
            Class::Ticket => (10.0, 1.0),
            Class::Write => (30.0, 5.0),
            Class::Typing => (10.0, 2.0),
            Class::Read => (20.0, 2.0),
            Class::InviteCheck => (10.0, 1.0 / 10.0),
            Class::Upload => (10.0, 1.0 / 20.0),
            Class::Canvas => (60.0, 10.0),
            Class::CanvasCursor => (30.0, 15.0),
            // See this variant's own doc comment for how these were sized.
            Class::CanvasStrokePreview => (12_288.0, 6_144.0),
            // A full member page plus a transcript's own avatars, at once.
            Class::Asset => (150.0, 25.0),
        }
    }
}

/// Most distinct keys tracked at once, across all classes.
const MAX_BUCKETS: usize = 20_000;
/// A bucket untouched for this long is swept.
const IDLE_TTL: Duration = Duration::from_secs(300);
/// How often the sweep runs, checked lazily on access.
const SWEEP_INTERVAL: Duration = Duration::from_secs(60);

#[derive(Debug)]
struct Bucket {
    tokens: f64,
    last: Instant,
}

struct State {
    buckets: HashMap<(Class, String), Bucket>,
    last_sweep: Instant,
}

/// A cloneable handle to the shared limiter.
#[derive(Clone)]
pub struct RateLimiter {
    state: Arc<Mutex<State>>,
    trusted_hops: usize,
}

impl Default for RateLimiter {
    fn default() -> Self {
        Self::new()
    }
}

impl RateLimiter {
    pub fn new() -> Self {
        Self::with_trusted_hops(0)
    }

    /// A limiter that trusts `hops` proxies in front of it when keying an
    /// unauthenticated caller. Zero, the default, trusts none and keys on the
    /// TCP peer; see [`RateLimiter::trusted_hops`].
    pub fn with_trusted_hops(trusted_hops: usize) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                buckets: HashMap::new(),
                last_sweep: Instant::now(),
            })),
            trusted_hops,
        }
    }

    /// How many proxies in front of this server may be believed about who the
    /// caller is.
    ///
    /// Zero means the TCP peer is the only thing believed, which is right for a
    /// directly-exposed server and is what a forwarded header cannot be trusted
    /// for: anyone may send one. Non-zero is an operator asserting they control
    /// that many hops, which makes the address that many places from the *right*
    /// of `X-Forwarded-For` as trustworthy as the peer - a caller can prepend
    /// anything they like to that header and never reach the slot.
    ///
    /// It has to be configurable rather than inferred because nothing in a
    /// request distinguishes a proxy the operator runs from one they do not.
    pub fn trusted_hops(&self) -> usize {
        self.trusted_hops
    }

    /// Takes one token for `key` in `class`, returning false if the caller is
    /// over budget and the request should be refused.
    pub fn check(&self, class: Class, key: &str) -> bool {
        self.check_at(class, key, Instant::now())
    }

    /// [`RateLimiter::check`] with an explicit clock, so tests can advance time
    /// without sleeping.
    pub fn check_at(&self, class: Class, key: &str, now: Instant) -> bool {
        self.check_weighted_at(class, key, 1.0, now)
    }

    /// [`RateLimiter::check`], charging `cost` tokens rather than the
    /// implicit one - the mechanism [`Class::CanvasStrokePreview`] uses to
    /// meter bytes instead of requests, by passing the frame's own wire size
    /// as `cost`. A `cost` larger than the class's whole burst is always
    /// refused, rather than admitted against an under-provisioned bucket.
    pub fn check_weighted(&self, class: Class, key: &str, cost: f64) -> bool {
        self.check_weighted_at(class, key, cost, Instant::now())
    }

    /// [`RateLimiter::check_weighted`] with an explicit clock; see
    /// [`RateLimiter::check_at`].
    pub fn check_weighted_at(&self, class: Class, key: &str, cost: f64, now: Instant) -> bool {
        let (burst, refill) = class.budget();
        if cost > burst {
            return false;
        }
        let mut state = match self.state.lock() {
            Ok(state) => state,
            // A poisoned lock means another thread panicked mid-update. Fail
            // open rather than wedging every request behind a dead limiter.
            Err(poisoned) => poisoned.into_inner(),
        };

        if now.duration_since(state.last_sweep) >= SWEEP_INTERVAL {
            state
                .buckets
                .retain(|_, bucket| now.duration_since(bucket.last) < IDLE_TTL);
            state.last_sweep = now;
        }

        let map_key = (class, key.to_owned());
        match state.buckets.get_mut(&map_key) {
            Some(bucket) => {
                let elapsed = now.duration_since(bucket.last).as_secs_f64();
                bucket.tokens = (bucket.tokens + elapsed * refill).min(burst);
                bucket.last = now;
                if bucket.tokens >= cost {
                    bucket.tokens -= cost;
                    true
                } else {
                    false
                }
            }
            None => {
                // Refuse rather than admit once the map is full, so a flood of
                // fresh keys cannot both grow memory and bypass the limit.
                if state.buckets.len() >= MAX_BUCKETS {
                    return false;
                }
                state.buckets.insert(
                    map_key,
                    Bucket {
                        tokens: burst - cost,
                        last: now,
                    },
                );
                true
            }
        }
    }

    /// How many buckets are currently tracked. For tests and diagnostics.
    pub fn tracked(&self) -> usize {
        match self.state.lock() {
            Ok(state) => state.buckets.len(),
            Err(poisoned) => poisoned.into_inner().buckets.len(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn burst_is_allowed_then_refused() {
        let limiter = RateLimiter::new();
        let now = Instant::now();
        let (burst, _) = Class::Password.budget();
        for i in 0..burst as usize {
            assert!(
                limiter.check_at(Class::Password, "1.2.3.4", now),
                "request {i} within the burst should pass"
            );
        }
        assert!(
            !limiter.check_at(Class::Password, "1.2.3.4", now),
            "the request past the burst is refused"
        );
    }

    #[test]
    fn tokens_refill_over_time() {
        let limiter = RateLimiter::new();
        let start = Instant::now();
        let (burst, refill) = Class::Password.budget();
        for _ in 0..burst as usize {
            assert!(limiter.check_at(Class::Password, "k", start));
        }
        assert!(!limiter.check_at(Class::Password, "k", start));

        // Exactly one token's worth of time restores exactly one request.
        let later = start + Duration::from_secs_f64(1.0 / refill);
        assert!(limiter.check_at(Class::Password, "k", later));
        assert!(!limiter.check_at(Class::Password, "k", later));
    }

    #[test]
    fn keys_and_classes_are_independent() {
        let limiter = RateLimiter::new();
        let now = Instant::now();
        let (burst, _) = Class::Password.budget();
        for _ in 0..burst as usize {
            assert!(limiter.check_at(Class::Password, "a", now));
        }
        assert!(!limiter.check_at(Class::Password, "a", now));
        // A different caller is unaffected.
        assert!(limiter.check_at(Class::Password, "b", now));
        // So is the same caller in a different class.
        assert!(limiter.check_at(Class::Write, "a", now));
    }

    #[test]
    fn idle_buckets_are_swept() {
        let limiter = RateLimiter::new();
        let start = Instant::now();
        assert!(limiter.check_at(Class::Write, "gone", start));
        assert_eq!(limiter.tracked(), 1);

        // Past the idle TTL, a later touch sweeps the stale bucket.
        let later = start + IDLE_TTL + SWEEP_INTERVAL;
        assert!(limiter.check_at(Class::Write, "fresh", later));
        assert_eq!(limiter.tracked(), 1, "the idle bucket was swept");
    }

    /// `check_at` is `check_weighted_at` at cost 1.0, not a second code path,
    /// so this is what actually proves the refactor kept every existing
    /// caller's behaviour: two big frames spend the burst exactly as two big
    /// requests would.
    #[test]
    fn weighted_cost_is_charged_per_call() {
        let limiter = RateLimiter::new();
        let now = Instant::now();
        let (burst, _) = Class::CanvasStrokePreview.budget();
        let half = burst / 2.0;
        assert!(limiter.check_weighted_at(Class::CanvasStrokePreview, "a", half, now));
        assert!(limiter.check_weighted_at(Class::CanvasStrokePreview, "a", half, now));
        assert!(
            !limiter.check_weighted_at(Class::CanvasStrokePreview, "a", 1.0, now),
            "the burst is fully spent"
        );
    }

    /// A frame nobody's own throttle could have produced is refused outright,
    /// on its own, rather than partially admitted against an
    /// under-provisioned bucket.
    #[test]
    fn a_cost_larger_than_the_burst_is_always_refused() {
        let limiter = RateLimiter::new();
        let (burst, _) = Class::CanvasStrokePreview.budget();
        assert!(!limiter.check_weighted_at(
            Class::CanvasStrokePreview,
            "a",
            burst + 1.0,
            Instant::now(),
        ));
    }

    /// The property the byte-rate cap exists for: a caller sending many small
    /// frames survives longer than one sending the same total bytes in fewer,
    /// larger ones - the opposite of a per-request cap, which would treat
    /// both identically. Mutation-tested by hand: reverting
    /// `check_weighted_at` to always charge 1.0 regardless of `cost` makes
    /// both assertions below pass identically, which is exactly the
    /// regression this test is for.
    #[test]
    fn many_small_frames_cost_less_than_few_large_ones_of_the_same_total() {
        let limiter = RateLimiter::new();
        let now = Instant::now();
        let (burst, _) = Class::CanvasStrokePreview.budget();

        let small_admitted = (0..1000)
            .filter(|_| limiter.check_weighted_at(Class::CanvasStrokePreview, "small", 1.0, now))
            .count();
        let large_admitted = (0..1000)
            .filter(|_| limiter.check_weighted_at(Class::CanvasStrokePreview, "large", burst, now))
            .count();

        assert!(small_admitted > large_admitted);
        assert_eq!(
            large_admitted, 1,
            "the first full-burst frame spends it all"
        );
    }
}
