// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! A durable per-account choice: how much of a channel's traffic is worth
//! waking a device for.
//!
//! Persisted in `users.notification_preference` (migration 0032);
//! [`crate::store::Store::notification_preference`] reads it and
//! [`crate::push::recipients`] is the only place it is enforced - the same
//! "read where the audience is computed, not filtered after the fact" shape
//! [`crate::push::recipients::message_recipients`]'s own doc comment already
//! uses for blocking.
//!
//! This is the account-wide default; `store/channel_notification_prefs.rs`
//! is a per-channel override of it, resolving through this same enum at the
//! same one choke point in `push::recipients` this doc comment predicted -
//! the way a channel overwrite narrows a role's base permission today rather
//! than needing a second evaluator.

/// What a message has to be, for this account, before it is worth a push.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum NotificationPreference {
    /// Every message in a channel this account can see. The default, and
    /// what every account already got before this preference existed.
    #[default]
    Everything,
    /// A direct `@`-mention, plus every message in a DM: see
    /// `push::recipients`'s own doc comment for why a DM always counts.
    Mentions,
    /// No push at all, ever, including a DM. The strongest of the three: an
    /// account that chose this is not waiting to be talked into an
    /// exception the way `Mentions`'s DM carve-out is.
    Nothing,
}

impl NotificationPreference {
    pub const fn as_str(self) -> &'static str {
        match self {
            NotificationPreference::Everything => "everything",
            NotificationPreference::Mentions => "mentions",
            NotificationPreference::Nothing => "nothing",
        }
    }

    pub fn parse(value: &str) -> Option<Self> {
        Some(match value {
            "everything" => NotificationPreference::Everything,
            "mentions" => NotificationPreference::Mentions,
            "nothing" => NotificationPreference::Nothing,
            _ => return None,
        })
    }
}

/// Minutes in a day, and the exclusive upper bound on a valid minute-of-day
/// value.
pub const MINUTES_PER_DAY: u16 = 1440;

/// A per-account quiet-hours window, in minutes since midnight UTC.
///
/// `start_minute` and `end_minute` are not ordered the way a plain range
/// would be: `start_minute > end_minute` is the ordinary shape for a window
/// that crosses midnight (23:00-08:00 is the motivating case, not an edge
/// case), so [`QuietHours::contains`] reads the pair as a clock face -
/// "wrap around to the next day" - rather than the naive `start <= now &&
/// now <= end` that only works for a window inside one calendar day.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct QuietHours {
    pub start_minute: u16,
    pub end_minute: u16,
}

impl QuietHours {
    /// Builds a window from wire values, refusing anything
    /// [`Store::set_quiet_hours`](crate::store::Store::set_quiet_hours)
    /// must not persist: either minute outside `0..MINUTES_PER_DAY`, or the
    /// two equal - a zero-length window and a full-day window would both
    /// have to spell the same pair, so neither is accepted and a caller who
    /// wants "always quiet" sets a 1439-minute window instead.
    pub fn parse(start_minute: i64, end_minute: i64) -> Option<Self> {
        let in_range = |m: i64| (0..i64::from(MINUTES_PER_DAY)).contains(&m);
        if !in_range(start_minute) || !in_range(end_minute) || start_minute == end_minute {
            return None;
        }
        Some(Self {
            start_minute: start_minute as u16,
            end_minute: end_minute as u16,
        })
    }

    /// Whether `minute_of_day` (0..1440, the caller's current UTC clock)
    /// falls inside this window. Start inclusive, end exclusive, in both
    /// directions: a window ending at 08:00 has already released its
    /// account by the 08:00 minute itself.
    pub fn contains(&self, minute_of_day: u16) -> bool {
        if self.start_minute < self.end_minute {
            (self.start_minute..self.end_minute).contains(&minute_of_day)
        } else {
            minute_of_day >= self.start_minute || minute_of_day < self.end_minute
        }
    }
}

/// The caller's current minute of day in UTC, from an epoch-millisecond
/// clock reading - always non-negative for any real wall clock, so the
/// remainder is never adjusted for a negative dividend the way a calendar
/// offset would need.
pub fn minute_of_day_utc(now_ms: i64) -> u16 {
    ((now_ms / 60_000) % i64::from(MINUTES_PER_DAY)) as u16
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_wire_spelling_round_trips() {
        for preference in [
            NotificationPreference::Everything,
            NotificationPreference::Mentions,
            NotificationPreference::Nothing,
        ] {
            assert_eq!(
                NotificationPreference::parse(preference.as_str()),
                Some(preference)
            );
        }
    }

    #[test]
    fn an_unrecognized_value_parses_to_none_rather_than_a_silent_guess() {
        assert_eq!(NotificationPreference::parse("silent"), None);
        assert_eq!(NotificationPreference::parse(""), None);
    }

    #[test]
    fn the_default_is_everything_so_an_existing_account_notices_nothing() {
        assert_eq!(
            NotificationPreference::default(),
            NotificationPreference::Everything
        );
    }

    #[test]
    fn a_window_inside_one_day_contains_only_its_own_span() {
        let window = QuietHours::parse(9 * 60, 17 * 60).unwrap();
        assert!(!window.contains(8 * 60 + 59), "one minute before open");
        assert!(window.contains(9 * 60), "start is inclusive");
        assert!(window.contains(16 * 60 + 59), "one minute before close");
        assert!(!window.contains(17 * 60), "end is exclusive");
    }

    /// 23:00-08:00, the motivating case: naive `start <= now && now <= end`
    /// logic answers every one of these backwards, since `start` (1380) is
    /// numerically greater than `end` (480).
    #[test]
    fn a_window_crossing_midnight_wraps_instead_of_going_empty() {
        let window = QuietHours::parse(23 * 60, 8 * 60).unwrap();
        assert!(
            window.contains(23 * 60),
            "23:00 itself, the inclusive start"
        );
        assert!(
            window.contains(23 * 60 + 30),
            "23:30, after start, before midnight"
        );
        assert!(window.contains(0), "midnight, the wrap point");
        assert!(
            window.contains(7 * 60 + 59),
            "07:59, one minute before close"
        );
        assert!(!window.contains(8 * 60), "08:00 itself, the exclusive end");
        assert!(
            !window.contains(12 * 60),
            "noon, squarely outside the window"
        );
        assert!(
            !window.contains(22 * 60 + 59),
            "22:59, one minute before open"
        );
    }

    #[test]
    fn parse_refuses_an_out_of_range_or_equal_pair() {
        assert_eq!(QuietHours::parse(-1, 60), None, "negative start");
        assert_eq!(
            QuietHours::parse(0, 1440),
            None,
            "end at the exclusive bound"
        );
        assert_eq!(
            QuietHours::parse(600, 600),
            None,
            "equal start and end is ambiguous between zero-length and all-day"
        );
    }

    #[test]
    fn minute_of_day_reads_the_utc_clock_face() {
        assert_eq!(minute_of_day_utc(0), 0, "the epoch itself is midnight");
        assert_eq!(
            minute_of_day_utc(23 * 60 * 60_000 + 59 * 60_000),
            23 * 60 + 59
        );
        assert_eq!(
            minute_of_day_utc(24 * 60 * 60_000),
            0,
            "a full day later is midnight again"
        );
    }
}
