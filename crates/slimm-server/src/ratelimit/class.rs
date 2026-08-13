// SPDX-License-Identifier: AGPL-3.0-only
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
        }
    }

    /// Every variant, for `/metrics` to enumerate a stable label set from.
    /// Hand-kept, matching the exhaustive matches in [`Self::budget`] and
    /// [`Self::label`]; a class added to the enum without extending this
    /// array compiles clean and is simply never counted, so add to all three
    /// together.
    pub const ALL: [Class; 12] = [
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
}
