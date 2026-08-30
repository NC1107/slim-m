// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The traffic classes [`super::RateLimiter`] meters, and their budgets.
//!
//! Split out of `ratelimit.rs` to keep that file under the review budget;
//! the limiter mechanism itself (buckets, sweeping, counting) stays there.

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
    ///
    /// Unauthenticated only - no `Authed`/`AuthedLimited` handler may charge
    /// this, enforced by `tests/rate_limit_coverage.rs`. An authenticated GET
    /// used to charge this too, on the reasoning that it was "just a read";
    /// that made every one of them fight `/version`'s own callers for a
    /// budget sized for a login screen, not a signed-in client. See
    /// [`Class::AuthedRead`] for where those moved.
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
    /// requests: a caller charges it through [`super::RateLimiter::check_weighted`]
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
    /// [`super::RateLimiter::check_weighted`], the way
    /// [`Class::CanvasStrokePreview`] already works - not a smaller budget
    /// here, which would break the avatar case this exists to serve.
    Asset,
    /// A cheap authenticated read: a list, a lookup, or a poll, never a
    /// mutation and never a real aggregation or outbound call.
    ///
    /// Every authenticated read used to be split between two other classes,
    /// both wrong for it: [`Class::Read`], whose own doc says it exists for
    /// *unauthenticated* metadata like `/version` and is tighter than
    /// [`Class::Write`] on the theory that nobody needs more than a handful
    /// of those - a theory that never held once an authenticated route
    /// started charging it too; or [`Class::Write`], which meant the voice
    /// roster, `/space/settings`, and the removed-members list shared one
    /// budget with token mint, heartbeat, and kick. This is the third class
    /// that should have existed from the start: every plain list/lookup GET
    /// behind `AuthedLimited<AUTHED_READ>` (`crate::http::extract`), plus
    /// the voice roster, `/space/settings`, `/members/removed`, and the
    /// cheap single-row analytics config reads (retention, canvas cap,
    /// screen-share cap). `/space/analytics`'s own stats query and
    /// `/metrics`'s live SFU probe are *not* here - both do real
    /// cross-table aggregation or an uncached outbound call, so they stay on
    /// [`Class::Write`]'s tighter budget even though they are GETs; see
    /// their own call sites for why.
    ///
    /// Sized against two concrete workloads rather than a round number.
    /// The sustained refill answers the polled voice roster: every unjoined
    /// voice channel a client is rendering re-fetches its roster every 15
    /// seconds (`voiceRosterPollInterval` in
    /// `client/packages/app/lib/src/providers/voice_roster.dart`), nudged
    /// early on a live join/leave rather than waiting out the interval. At
    /// this refill, over 100 simultaneously-open voice channels could each
    /// poll on their own 15-second cycle forever without ever touching the
    /// burst, leaving headroom for every other read a client makes in the
    /// same stretch. The burst answers a reconnect: `ChannelRefresher`
    /// (`client/packages/app/lib/src/providers/channel_refresher.dart`)
    /// fetches every channel's and DM's read marker concurrently the moment
    /// a dropped socket comes back, alongside the channel/category/DM lists
    /// and the notification-override and block lists two other controllers
    /// fire at the same time. A deployment with more open channels than the
    /// burst covers does not fail that reconnect: the extra read-marker
    /// fetches simply wait out the refill and land a couple of seconds
    /// later, the same graceful-degradation shape [`Class::Canvas`]'s own
    /// doc describes, not a 429 storm.
    AuthedRead,
    /// Searching a third-party GIF provider, and picking a result to attach.
    ///
    /// Tighter than [`Class::Read`] on purpose: unlike every other read this
    /// server serves, each request here is a real outbound call to a
    /// provider this deployment has its own, possibly-metered API key with -
    /// a client bug or a tight retype loop should not be able to spend that
    /// budget as fast as it can open connections. Sized for a person typing
    /// a query, pausing, then picking a result, not for a per-keystroke
    /// search; see `http::gifs` for the debounce that keeps it that shape in
    /// practice.
    Gif,
}

impl Class {
    /// (burst, refill per second). For [`Class::CanvasStrokePreview`] the
    /// unit is bytes, not requests; see its own doc.
    pub(super) const fn budget(self) -> (f64, f64) {
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
            Class::Gif => (10.0, 1.0),
            // See this variant's own doc comment for the roster and reconnect math.
            Class::AuthedRead => (40.0, 8.0),
        }
    }

    /// Every variant, for `/metrics` to enumerate a stable label set from.
    /// Hand-kept, matching the exhaustive matches in [`Self::budget`] and
    /// [`Self::label`]; a class added to the enum without extending this
    /// array compiles clean and is simply never counted, so add to all three
    /// together.
    pub const ALL: [Class; 14] = [
        Class::Password,
        Class::Refresh,
        Class::Ticket,
        Class::Write,
        Class::Typing,
        Class::Read,
        Class::InviteCheck,
        Class::Upload,
        Class::Canvas,
        Class::CanvasCursor,
        Class::CanvasStrokePreview,
        Class::Asset,
        Class::Gif,
        Class::AuthedRead,
    ];

    /// The Prometheus label value for this class: lowercase, snake_case, and
    /// stable across releases since a dashboard or alert may key on it.
    pub fn label(self) -> &'static str {
        match self {
            Class::Password => "password",
            Class::Refresh => "refresh",
            Class::Ticket => "ticket",
            Class::Write => "write",
            Class::Typing => "typing",
            Class::Read => "read",
            Class::InviteCheck => "invite_check",
            Class::Upload => "upload",
            Class::Canvas => "canvas",
            Class::CanvasCursor => "canvas_cursor",
            Class::CanvasStrokePreview => "canvas_stroke_preview",
            Class::Asset => "asset",
            Class::Gif => "gif",
            Class::AuthedRead => "authed_read",
        }
    }
}

#[cfg(test)]
mod all_tests {
    use super::*;

    /// `ALL` exists so `/metrics` never has to be told about a new class by
    /// hand; if this ever drifts, a class silently stops being counted.
    #[test]
    fn all_lists_every_variant_exactly_once() {
        let mut seen = std::collections::HashSet::new();
        for class in Class::ALL {
            assert!(
                seen.insert(class),
                "{class:?} appears more than once in ALL"
            );
        }
        assert_eq!(seen.len(), Class::ALL.len());
    }

    /// The label is a Prometheus dimension, so two classes sharing one would
    /// silently merge their counters. Each must also be the lowercase snake_case
    /// the doc promises a dashboard can key on.
    #[test]
    fn every_label_is_unique_and_snake_case() {
        let mut seen = std::collections::HashSet::new();
        for class in Class::ALL {
            let label = class.label();
            assert!(!label.is_empty(), "{class:?} has an empty label");
            assert!(
                label
                    .chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_'),
                "{class:?} label {label:?} is not lowercase snake_case"
            );
            assert!(seen.insert(label), "two classes share the label {label:?}");
        }
    }

    /// A bucket with a non-positive burst can never admit a request, and a
    /// non-positive refill never recovers one; either is a budget typo that
    /// would wedge every caller of that class.
    #[test]
    fn every_budget_is_positive() {
        for class in Class::ALL {
            let (burst, refill) = class.budget();
            assert!(burst > 0.0, "{class:?} has a non-positive burst {burst}");
            assert!(refill > 0.0, "{class:?} has a non-positive refill {refill}");
        }
    }
}
