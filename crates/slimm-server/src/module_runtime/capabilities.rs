// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The mediated-capability surface, per decision 0023 - the gate a module's
//! `slim.host_call` requests pass through.
//!
//! This is Phase B of that record: the gate is real, but no capability is
//! implemented. The surface ships dark - [`CapabilitySurface::Disabled`] is the
//! default and the only value the live run paths pass today, so a module still
//! may import nothing and every `host_call` is refused until an owner turns the
//! surface on (a future, deliberate step) and a capability is added to
//! [`REGISTRY`].
//!
//! Everything here fails closed: an off surface, an unapproved capability, a
//! malformed request, or a capability the host does not implement all return a
//! clean `{ "ok": false, "error": ... }`, never a trap and never anything from
//! outside the module. The module is never trusted to have sent a well-formed
//! or authorized request.

use serde::Deserialize;
use serde_json::json;

/// The capabilities the host actually implements. Empty in Phase B: the
/// registry exists so a later phase adds `kv.store` (and its handler) here in
/// one place, and so a capability a manifest declared but the host does not
/// implement is still refused rather than silently doing nothing.
const REGISTRY: &[&str] = &[];

/// Whether the capability surface is available to a module run, and which
/// capabilities the space approved for it.
#[derive(Debug, Clone, Default)]
pub enum CapabilitySurface {
    /// The surface is off (the default, and every live path today). A module
    /// may import nothing; `slim.host_call` is refused like any other import.
    #[default]
    Disabled,
    /// The surface is on for this run, with the space-approved capability set
    /// recorded at install (decision 0021's `approved_capabilities`).
    Enabled { approved: Vec<String> },
}

impl CapabilitySurface {
    /// Whether this run may link the single `slim.host_call` import: only when
    /// the surface is on and the space approved at least one capability for the
    /// module. A module importing it under any other condition is refused at
    /// instantiation (see `host.rs`).
    pub fn allows_host_call(&self) -> bool {
        matches!(self, CapabilitySurface::Enabled { approved } if !approved.is_empty())
    }

    /// Dispatches one `host_call` request to the registry, returning the UTF-8
    /// JSON response bytes. See the module doc: this fails closed on every
    /// path, and in Phase B every path is a refusal because [`REGISTRY`] is
    /// empty.
    pub fn dispatch(&self, request: &[u8]) -> Vec<u8> {
        let approved = match self {
            CapabilitySurface::Enabled { approved } => approved,
            CapabilitySurface::Disabled => return refusal("the capability surface is off"),
        };
        let parsed: HostCallRequest = match serde_json::from_slice(request) {
            Ok(parsed) => parsed,
            Err(_) => return refusal("malformed host_call request"),
        };
        if !approved.iter().any(|c| c == &parsed.capability) {
            return refusal(&format!("capability not approved: {}", parsed.capability));
        }
        if !REGISTRY.contains(&parsed.capability.as_str()) {
            // Declared and approved, but the host implements no such capability yet (Phase B); a later phase routes to a handler here.
            return refusal(&format!("capability not available: {}", parsed.capability));
        }
        // Unreachable in Phase B (REGISTRY is empty); the handler dispatch lands here.
        refusal(&format!("capability not available: {}", parsed.capability))
    }
}

/// The envelope every `host_call` request shares: which capability it targets.
/// Its arguments are capability-specific and parsed by the handler, not here.
#[derive(Deserialize)]
struct HostCallRequest {
    capability: String,
}

fn refusal(message: &str) -> Vec<u8> {
    serde_json::to_vec(&json!({ "ok": false, "error": message }))
        .unwrap_or_else(|_| br#"{"ok":false,"error":"host error"}"#.to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn text(bytes: &[u8]) -> String {
        String::from_utf8(bytes.to_vec()).unwrap()
    }

    #[test]
    fn a_disabled_surface_allows_no_host_call_and_refuses_every_request() {
        let surface = CapabilitySurface::Disabled;
        assert!(!surface.allows_host_call());
        assert!(
            text(&surface.dispatch(br#"{"capability":"kv.store"}"#)).contains("surface is off")
        );
    }

    #[test]
    fn enabled_with_no_approved_capability_allows_no_host_call() {
        let surface = CapabilitySurface::Enabled { approved: vec![] };
        assert!(!surface.allows_host_call());
    }

    #[test]
    fn enabled_with_an_approved_capability_allows_host_call() {
        let surface = CapabilitySurface::Enabled {
            approved: vec!["kv.store".to_owned()],
        };
        assert!(surface.allows_host_call());
    }

    #[test]
    fn an_unapproved_capability_is_refused() {
        let surface = CapabilitySurface::Enabled {
            approved: vec!["message.post".to_owned()],
        };
        let out = text(&surface.dispatch(br#"{"capability":"kv.store"}"#));
        assert!(out.contains("not approved: kv.store"), "{out}");
    }

    #[test]
    fn an_approved_but_unimplemented_capability_is_refused_cleanly() {
        // Phase B: the gate passes (approved) but the registry is empty, so even an approved capability does nothing yet.
        let surface = CapabilitySurface::Enabled {
            approved: vec!["kv.store".to_owned()],
        };
        let out = text(&surface.dispatch(br#"{"capability":"kv.store","op":"get"}"#));
        assert!(out.contains("not available: kv.store"), "{out}");
        assert!(out.contains(r#""ok":false"#), "{out}");
    }

    #[test]
    fn a_malformed_request_is_refused_not_panicked() {
        let surface = CapabilitySurface::Enabled {
            approved: vec!["kv.store".to_owned()],
        };
        assert!(text(&surface.dispatch(b"not json")).contains("malformed"));
    }
}
