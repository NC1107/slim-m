// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Validating a member's free-text profile fields, split out of `users.rs` so
//! they have a home to be unit-tested in and the handler file stays under its
//! line budget. Pure functions of their argument.

use super::auth::is_disallowed_label_char;
use super::error::ApiError;

const STATUS_TEXT_MAX_CHARS: usize = 80;
const PRONOUNS_MAX_CHARS: usize = 40;
const ABOUT_MAX_CHARS: usize = 190;
/// Exclusive upper bound on `profile_color`: the number of hues in the
/// design system's closed categorical set (`AppCanvasColors.cursors`).
pub(super) const PROFILE_COLOR_COUNT: i64 = 6;

/// Trims a free-text profile field, bounds it to `max_chars`, and rejects the
/// control and text-direction characters a display string must never carry.
/// An empty result clears the field (returns `None`) rather than storing a
/// blank - the shared shape [`validate_status_text`], [`validate_pronouns`]
/// and [`validate_about`] all follow.
fn validate_short_field(
    value: &str,
    max_chars: usize,
    too_long: &'static str,
) -> Result<Option<String>, ApiError> {
    let trimmed = value.trim();
    if trimmed.chars().count() > max_chars {
        return Err(ApiError::BadRequest(too_long));
    }
    if trimmed.chars().any(is_disallowed_label_char) {
        return Err(ApiError::BadRequest(
            "must not contain control or text-direction characters",
        ));
    }
    Ok(if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_owned())
    })
}

/// Trims a status line, bounds it, and rejects the control and
/// text-direction characters a display string must never carry. An empty
/// result clears the status (returns `None`) rather than storing a blank.
pub(super) fn validate_status_text(status_text: &str) -> Result<Option<String>, ApiError> {
    validate_short_field(
        status_text,
        STATUS_TEXT_MAX_CHARS,
        "status must be at most 80 characters",
    )
}

/// A short self-described pronoun set ("she/her"), shown on the member card
/// beside the `@handle`.
pub(super) fn validate_pronouns(pronouns: &str) -> Result<Option<String>, ApiError> {
    validate_short_field(
        pronouns,
        PRONOUNS_MAX_CHARS,
        "pronouns must be at most 40 characters",
    )
}

/// A short "about" line, shown on the member card under the status.
pub(super) fn validate_about(about: &str) -> Result<Option<String>, ApiError> {
    validate_short_field(
        about,
        ABOUT_MAX_CHARS,
        "about must be at most 190 characters",
    )
}

/// An index into the design system's closed categorical colour set. Bounded
/// here rather than left to render as whatever a client sends, the same
/// reason every enum-shaped integer field in this API is range-checked
/// server-side instead of trusted.
pub(super) fn validate_profile_color(color: i64) -> Result<i64, ApiError> {
    if !(0..PROFILE_COLOR_COUNT).contains(&color) {
        return Err(ApiError::BadRequest("profile_color is out of range"));
    }
    Ok(color)
}

#[cfg(test)]
mod tests {
    use super::{
        PROFILE_COLOR_COUNT, validate_about, validate_profile_color, validate_pronouns,
        validate_status_text,
    };

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

    #[test]
    fn pronouns_are_trimmed_and_bounded_at_forty() {
        assert!(matches!(validate_pronouns("  she/her  "), Ok(Some(s)) if s == "she/her"));
        assert!(matches!(validate_pronouns(""), Ok(None)));
        assert!(validate_pronouns(&"a".repeat(40)).is_ok());
        assert!(validate_pronouns(&"a".repeat(41)).is_err());
    }

    #[test]
    fn about_is_trimmed_and_bounded_at_190() {
        assert!(matches!(validate_about("  hi  "), Ok(Some(s)) if s == "hi"));
        assert!(matches!(validate_about(""), Ok(None)));
        assert!(validate_about(&"a".repeat(190)).is_ok());
        assert!(validate_about(&"a".repeat(191)).is_err());
    }

    #[test]
    fn profile_color_must_be_a_valid_index() {
        assert!(validate_profile_color(0).is_ok());
        assert!(validate_profile_color(PROFILE_COLOR_COUNT - 1).is_ok());
        assert!(validate_profile_color(-1).is_err());
        assert!(validate_profile_color(PROFILE_COLOR_COUNT).is_err());
    }
}
