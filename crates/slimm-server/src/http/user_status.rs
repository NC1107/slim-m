// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Validating a member's free-text status line, split out of `users.rs` so it
//! has a home to be unit-tested in and the handler file stays under its line
//! budget. A pure function of its argument.

use super::auth::is_disallowed_label_char;
use super::error::ApiError;

const STATUS_TEXT_MAX_CHARS: usize = 80;

/// Trims a status line, bounds it, and rejects the control and
/// text-direction characters a display string must never carry. An empty
/// result clears the status (returns `None`) rather than storing a blank.
pub(super) fn validate_status_text(status_text: &str) -> Result<Option<String>, ApiError> {
    let trimmed = status_text.trim();
    if trimmed.chars().count() > STATUS_TEXT_MAX_CHARS {
        return Err(ApiError::BadRequest("status must be at most 80 characters"));
    }
    if trimmed.chars().any(is_disallowed_label_char) {
        return Err(ApiError::BadRequest(
            "status must not contain control or text-direction characters",
        ));
    }
    Ok(if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_owned())
    })
}

#[cfg(test)]
mod tests {
    use super::validate_status_text;

    #[test]
    fn a_plain_status_is_trimmed_and_kept() {
        assert!(matches!(validate_status_text("  hi  "), Ok(Some(s)) if s == "hi"));
    }

    /// An empty or whitespace-only status clears the field rather than storing
    /// a blank string.
    #[test]
    fn an_empty_or_whitespace_status_clears_it() {
        assert!(matches!(validate_status_text(""), Ok(None)));
        assert!(matches!(validate_status_text("   "), Ok(None)));
    }

    #[test]
    fn the_length_cap_is_inclusive() {
        assert!(validate_status_text(&"a".repeat(80)).is_ok());
        assert!(validate_status_text(&"a".repeat(81)).is_err());
    }

    /// The same anti-spoofing guard a display name gets: a status may not carry
    /// a control character or a bidi override.
    #[test]
    fn control_and_direction_characters_are_refused() {
        assert!(validate_status_text("a\u{202E}b").is_err());
        assert!(validate_status_text("a\nb").is_err());
    }
}
