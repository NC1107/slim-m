// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! What to do with a failure after a message has committed.

/// The value, or its default with the failure logged. Once a message is stored,
/// failing the request would make a retry see it as already sent and never
/// announce it, so the live event must still go out with what is available.
pub(super) fn after_commit<T: Default>(what: &str, result: anyhow::Result<T>) -> T {
    result.unwrap_or_else(|err| {
        tracing::warn!(%err, "message stored, but {what} failed");
        T::default()
    })
}
