// SPDX-License-Identifier: AGPL-3.0-only
//! This process's own resident memory, for the analytics screen's one
//! recorded series. Linux-only: the server ships only as a Linux container
//! (see `docker/server.Dockerfile`), and a platform this cannot read from
//! just skips that sample rather than failing the read it rides on.

/// Resident set size in bytes, or `None` if `/proc/self/status` could not be
/// read or parsed. Never panics: a malformed or missing line is a skipped
/// sample, not a failed request.
#[cfg(target_os = "linux")]
pub fn current_rss_bytes() -> Option<i64> {
    let status = std::fs::read_to_string("/proc/self/status").ok()?;
    for line in status.lines() {
        if let Some(rest) = line.strip_prefix("VmRSS:") {
            let kb: i64 = rest.split_whitespace().next()?.parse().ok()?;
            return Some(kb * 1024);
        }
    }
    None
}

#[cfg(not(target_os = "linux"))]
pub fn current_rss_bytes() -> Option<i64> {
    None
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::current_rss_bytes;

    #[test]
    fn reads_a_positive_value_on_linux() {
        assert!(current_rss_bytes().is_some_and(|bytes| bytes > 0));
    }
}
