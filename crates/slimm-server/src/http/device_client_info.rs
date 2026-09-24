// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Validating `client_kind`/`client_version`, split out of `auth.rs` so it has
//! a home to be unit-tested in and that file stays under its line budget. A
//! pure function of its argument, the same shape `user_status.rs` follows.

use super::auth::is_disallowed_label_char;
use super::error::ApiError;

/// Bounds and sanitises `client_kind`/`client_version`: short, optional
/// strings a client reports about itself for the devices list. Blank clears
/// to `None`, the same convention `http::user_status`'s free-text fields use.
pub(super) fn validate_client_info(
    value: &str,
    max_chars: usize,
) -> Result<Option<String>, ApiError> {
    let trimmed = value.trim();
    if trimmed.chars().count() > max_chars {
        return Err(ApiError::BadRequest("client info is too long"));
    }
    if trimmed.chars().any(is_disallowed_label_char) {
        return Err(ApiError::BadRequest(
            "client info must not contain control or text-direction characters",
        ));
    }
    Ok((!trimmed.is_empty()).then(|| trimmed.to_owned()))
}

#[cfg(test)]
mod tests {
    use super::validate_client_info;

    #[test]
    fn client_info_is_trimmed_and_blank_clears_it() {
        assert!(matches!(validate_client_info("  desktop  ", 16), Ok(Some(s)) if s == "desktop"));
        assert!(matches!(validate_client_info("", 16), Ok(None)));
        assert!(matches!(validate_client_info("   ", 16), Ok(None)));
    }

    #[test]
    fn client_info_is_bounded_and_refuses_spoofing_characters() {
        assert!(validate_client_info(&"a".repeat(16), 16).is_ok());
        assert!(validate_client_info(&"a".repeat(17), 16).is_err());
        assert!(validate_client_info("a\u{202E}b", 16).is_err());
    }
}
