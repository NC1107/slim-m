// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The build identifier `/version` reports, so two deploys of one version differ.

/// Longest identifier reported; a short git SHA is enough to tell builds apart.
const MAX_LEN: usize = 12;

/// The identifier baked in at compile time from `SLIMM_BUILD_ID`, if any.
///
/// Read at compile time because the runtime image has no repo and a release
/// binary has no environment of its own. A plain `cargo run` reports none.
pub fn current() -> Option<String> {
    from_raw(option_env!("SLIMM_BUILD_ID"))
}

/// Trim, shorten, and reject anything that is not a plain token, so a stray
/// path or hostname in the variable can never reach an unauthenticated caller.
pub fn from_raw(raw: Option<&str>) -> Option<String> {
    let id: String = raw?.trim().chars().take(MAX_LEN).collect();
    let plain = !id.is_empty() && id.chars().all(|c| c.is_ascii_alphanumeric());
    plain.then_some(id)
}

#[cfg(test)]
mod tests {
    use super::from_raw;

    #[test]
    fn a_full_sha_is_shortened() {
        let sha = "919aa49b0c1d2e3f4a5b6c7d8e9f001122334455";
        assert_eq!(from_raw(Some(sha)).as_deref(), Some("919aa49b0c1d"));
    }

    #[test]
    fn an_unset_or_blank_value_is_absent() {
        assert_eq!(from_raw(None), None);
        assert_eq!(from_raw(Some("  ")), None);
    }

    #[test]
    fn anything_but_a_plain_token_is_absent() {
        assert_eq!(from_raw(Some("/home/ci/build")), None);
        assert_eq!(from_raw(Some("host.example.com")), None);
    }
}
