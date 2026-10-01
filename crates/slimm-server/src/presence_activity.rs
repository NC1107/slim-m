// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! What a connected user says they are doing right now: listening to a track
//! or playing a game.
//!
//! Ephemeral like the rest of presence (decision 0044): it lives on the
//! user's [`crate::presence::PresenceTracker`] entry, so it disappears with
//! their last socket and is never written to SQLite.

use serde::{Deserialize, Serialize};

/// Longest title or subtitle, in characters. The client truncates to the same
/// number, so a well-behaved sender never sees the refusal.
pub const MAX_TEXT_CHARS: usize = 128;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
/// Serialised lowercase, matching the OpenAPI enum.
#[serde(rename_all = "snake_case")]
pub enum ActivityKind {
    Listening,
    Playing,
}

/// One activity as it goes over the wire. There is deliberately no image
/// field yet: art is never fetched from a sender-supplied URL (decision 0044).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
/// Unknown fields are refused so no image URL can ride in.
#[serde(deny_unknown_fields)]
pub struct Activity {
    #[serde(rename = "type")]
    pub kind: ActivityKind,
    pub title: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub subtitle: Option<String>,
    /// Epoch milliseconds the activity began, when the source knows.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub started_at: Option<i64>,
}

impl Activity {
    /// Refuses an empty, over-long or hidden-character text rather than
    /// trimming it, so what viewers read is exactly what the sender sent.
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.title.trim().is_empty() {
            return Err("activity title must not be empty");
        }
        let subtitle = self.subtitle.as_deref().unwrap_or("");
        for text in [self.title.as_str(), subtitle] {
            if text.chars().count() > MAX_TEXT_CHARS {
                return Err("activity text is too long");
            }
            if text.chars().any(crate::hidden_chars::is_hidden_char) {
                return Err("activity text must not contain control characters");
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(title: &str) -> Activity {
        Activity {
            kind: ActivityKind::Listening,
            title: title.to_owned(),
            subtitle: None,
            started_at: None,
        }
    }

    #[test]
    fn accepts_the_cap_and_refuses_one_past_it() {
        assert!(sample(&"a".repeat(MAX_TEXT_CHARS)).validate().is_ok());
        assert!(sample(&"a".repeat(MAX_TEXT_CHARS + 1)).validate().is_err());
    }

    #[test]
    fn counts_characters_not_bytes() {
        assert!(sample(&"\u{e9}".repeat(MAX_TEXT_CHARS)).validate().is_ok());
    }

    #[test]
    fn refuses_empty_control_and_direction_text() {
        assert!(sample("  ").validate().is_err());
        assert!(sample("a\nb").validate().is_err());
        assert!(sample("a\u{202e}b").validate().is_err());
        // These three were accepted while this file kept a list of its own.
        for mark in ['\u{061C}', '\u{2060}', '\u{FEFF}'] {
            assert!(sample(&format!("a{mark}b")).validate().is_err(), "{mark:?}");
        }
    }
}
