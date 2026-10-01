// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! A deployment-wide cursor over moderation events, so a consumer that was
//! offline can tell it missed some without being handed any history.
//!
//! The five events `member.timeout`, `member.removed`, `member.restored`,
//! `member.role_changed` and `role.changed` are delivered to every connection
//! and have no per-channel stream a `/sync` scope could resume. Each is
//! stamped here with a strictly increasing number, and the connect `hello`
//! carries the current head. A consumer that persists the last number it saw
//! compares it to the head on reconnect: a larger head means events landed
//! while it was away.
//!
//! The number is clock-seeded rather than stored: it starts at boot time and
//! never repeats or decreases, so it stays monotonic across restarts without a
//! table. The price is one conservative signal after each restart, since the
//! head is then the boot time, which is later than anything a consumer saw
//! before. That is the safe direction for an audit trail: "you may have
//! missed events" when unsure, never silence.
//!
//! A backward clock step across a restart can make the head smaller than a
//! number a consumer already saw, a silent false negative this does not guard
//! against. The `hello` also hands the head to every connection, so any member
//! learns roughly when the last moderation event happened; that is accepted.
//!
//! Nothing here exposes what happened. The number carries no permission, so
//! the gates on `GET /roles`, `/reports/history` and `/members/removed` stay
//! exactly as they were.

use std::sync::atomic::{AtomicU64, Ordering};

use super::Event;

pub(super) struct ModerationClock {
    last: AtomicU64,
}

impl ModerationClock {
    pub(super) fn new() -> Self {
        Self {
            last: AtomicU64::new(now_ms()),
        }
    }

    pub(super) fn head(&self) -> u64 {
        self.last.load(Ordering::Acquire)
    }

    pub(super) fn advance(&self) -> u64 {
        let now = now_ms();
        let previous = self
            .last
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |last| {
                Some(now.max(last + 1))
            })
            .unwrap_or(now);
        now.max(previous + 1)
    }
}

fn now_ms() -> u64 {
    u64::try_from(crate::store::now_ms()).unwrap_or(0)
}

/// Whether this event belongs to the moderation trail and so carries a number.
pub(super) fn is_moderation(event: &Event) -> bool {
    matches!(
        event,
        Event::MemberTimeoutChanged { .. }
            | Event::MemberRemoved(_)
            | Event::MemberRestored(_)
            | Event::MemberRoleChanged { .. }
            | Event::RoleChanged { .. }
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_tight_loop_never_repeats_or_goes_backwards() {
        let clock = ModerationClock::new();
        let mut previous = clock.head();
        for _ in 0..10_000 {
            let next = clock.advance();
            assert!(next > previous);
            previous = next;
        }
        assert_eq!(clock.head(), previous);
    }
}
