// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The one classifier for characters that change what a reader sees without
//! changing what the text does (trojan source, CVE-2021-42574).

use super::auth::is_disallowed_label_char;

/// True for a control, text-direction or zero-width character. `pub(crate)` so
/// code runs and module manifests refuse the same set instead of two lists.
pub(crate) fn is_hidden_char(c: char) -> bool {
    is_disallowed_label_char(c) || c == '\u{061C}'
}

#[cfg(test)]
mod tests {
    use super::is_hidden_char;

    #[test]
    fn hidden_characters_are_told_apart_from_ordinary_text() {
        for hidden in ['\u{202E}', '\u{200B}', '\u{061C}', '\u{0}', '\u{2066}'] {
            assert!(is_hidden_char(hidden), "{hidden:?}");
        }
        for plain in ['a', ' ', '\u{e9}', '\u{4e2d}'] {
            assert!(!is_hidden_char(plain), "{plain:?}");
        }
    }
}
