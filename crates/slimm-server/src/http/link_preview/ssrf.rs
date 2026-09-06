// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The SSRF guard for link unfurling: validates an arbitrary, member-supplied
//! URL against the range check in [`crate::net_guard`].
//!
//! Two documented reqwest bypass classes shape this (see decision 0019):
//! a hostname whose first resolved address is public but whose second is
//! loopback (reqwest tries every address, so validating only the first lets
//! it fall through), and a numeric IP literal (which the `url` crate parses
//! directly, so reqwest never calls a resolver at all for it). The first is
//! why [`crate::net_guard::GuardResolver`] rejects the whole name if *any*
//! resolved address is blocked; the second is why [`validate`] checks a
//! literal host itself.

use std::net::IpAddr;

use url::Url;

pub(super) use crate::net_guard::GuardResolver;
use crate::net_guard::is_blocked;

/// Why a URL was refused before or during a fetch. Deliberately coarse: a
/// caller (and a member) learns only that the link could not be previewed,
/// never which internal address a probe did or did not reach.
#[derive(Debug, PartialEq, Eq)]
pub(super) enum UrlError {
    /// Not a well-formed http(s) URL.
    Invalid,
    /// Well-formed, but points at an address this server must not dial.
    Blocked,
}

/// A URL validated for scheme and, when its host is a numeric literal, for
/// address range - the half of the guard that runs before reqwest, because a
/// literal host skips the resolver entirely.
///
/// [allow_private] lets a test reach the loopback a fake upstream binds to. It
/// is only ever `true` from `LinkPreviews::for_test`; every production path
/// passes `false`, so the block ranges always apply there.
pub(super) fn validate(raw: &str, allow_private: bool) -> Result<Url, UrlError> {
    let url = Url::parse(raw).map_err(|_| UrlError::Invalid)?;
    if url.scheme() != "http" && url.scheme() != "https" {
        return Err(UrlError::Invalid);
    }
    match url.host() {
        None => Err(UrlError::Invalid),
        // A literal host, already normalized from any decimal/hex/octal form.
        Some(url::Host::Ipv4(v4)) if !allow_private && is_blocked(IpAddr::V4(v4)) => {
            Err(UrlError::Blocked)
        }
        Some(url::Host::Ipv6(v6)) if !allow_private && is_blocked(IpAddr::V6(v6)) => {
            Err(UrlError::Blocked)
        }
        Some(_) => Ok(url),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_url_rejects_numeric_literal_encodings_of_loopback() {
        // The three encodings from the vaultwarden advisory, all 127.0.0.1.
        for raw in [
            "http://2130706433/",
            "http://0x7f000001/",
            "http://0177.0.0.1/",
            "http://127.0.0.1/",
            "http://[::1]/",
        ] {
            assert_eq!(validate(raw, false), Err(UrlError::Blocked), "{raw}");
        }
    }

    #[test]
    fn validate_url_rejects_non_http_schemes_and_junk() {
        for raw in ["file:///etc/passwd", "gopher://x/", "ftp://x/", "not a url"] {
            assert_eq!(validate(raw, false), Err(UrlError::Invalid), "{raw}");
        }
    }

    #[test]
    fn validate_url_allows_an_ordinary_https_link() {
        assert!(validate("https://example.com/a/b?c=d", false).is_ok());
    }
}
