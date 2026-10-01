// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The one rule for a manifest's `artifact.path`: plain segments under the
//! module's own repo, so `Url::join` can never resolve it anywhere else.

/// Segments of letters, digits and `-_.+@`, none empty and none a dot segment.
/// An allowlist rather than a blocklist, because `%2e%2e` and `\` are both
/// read as path structure by `Url::join` and a blocklist keeps missing one.
pub(super) fn is_plain_relative_path(path: &str) -> bool {
    path.split('/').all(|segment| {
        !segment.is_empty()
            && segment != "."
            && segment != ".."
            && segment
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'+' | b'@'))
    })
}
