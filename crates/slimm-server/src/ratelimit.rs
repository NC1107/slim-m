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
}

impl Class {
    /// (burst, refill per second).
    const fn budget(self) -> (f64, f64) {
        match self {
            Class::Password => (5.0, 1.0 / 6.0),
            Class::Refresh => (10.0, 1.0 / 2.0),
            Class::Ticket => (10.0, 1.0),
            Class::Write => (30.0, 5.0),
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
}

impl Default for RateLimiter {
    fn default() -> Self {
        Self::new()
    }
}

impl RateLimiter {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                buckets: HashMap::new(),
                last_sweep: Instant::now(),
            })),
        }
    }

    /// Takes one token for `key` in `class`, returning false if the caller is
    /// over budget and the request should be refused.
    pub fn check(&self, class: Class, key: &str) -> bool {
        self.check_at(class, key, Instant::now())
    }

    /// [`RateLimiter::check`] with an explicit clock, so tests can advance time
    /// without sleeping.
    pub fn check_at(&self, class: Class, key: &str, now: Instant) -> bool {
        let (burst, refill) = class.budget();
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
                if bucket.tokens >= 1.0 {
                    bucket.tokens -= 1.0;
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
                        tokens: burst - 1.0,
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
}
