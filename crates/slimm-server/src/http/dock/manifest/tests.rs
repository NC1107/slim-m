// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Tests for [`super::manifest`], split into this path-based child module
//! purely to hold `manifest.rs` under the file-budget ceiling.

use super::*;

const GOOD_INDEX: &str = r#"{
    "schema": 1,
    "modules": [
        {"id": "code-exec", "name": "Code Blocks", "version": "0.1.0", "summary": "runs code"}
    ]
}"#;

const GOOD_MANIFEST: &str = r#"{
    "schema": 1,
    "id": "code-exec",
    "name": "Code Blocks",
    "version": "0.1.0",
    "summary": "runs code",
    "author": "slim-m",
    "artifact": {
        "kind": "wasm",
        "path": "modules/code-exec/0.1.0/module.wasm",
        "sha256": "0000000000000000000000000000000000000000000000000000000000000000"
    },
    "runtime": {"backend": "wasm", "limits": {"memory_mb": 64, "wall_ms": 2000, "fuel": 500000000}},
    "permissions": [
        {"key": "run", "name": "Execute code blocks", "description": "run a snippet"}
    ],
    "capabilities": ["command.register", "message.post"],
    "extension_points": [
        {"kind": "command", "name": "run", "description": "runs it"}
    ]
}"#;

#[test]
fn parses_the_live_registry_shapes() {
    let index = parse_index(GOOD_INDEX.as_bytes()).unwrap();
    assert_eq!(index.len(), 1);
    assert_eq!(index[0].id, "code-exec");

    let manifest = parse_manifest(GOOD_MANIFEST.as_bytes()).unwrap();
    assert_eq!(manifest.id, "code-exec");
    assert_eq!(manifest.permissions.len(), 1);
    assert_eq!(manifest.permissions[0].key, "run");
    assert_eq!(manifest.artifact.sha256.len(), 64);
}

#[test]
fn rejects_malformed_json() {
    assert!(matches!(
        parse_manifest(b"not json"),
        Err(ManifestError::Malformed(_))
    ));
    assert!(matches!(
        parse_index(b"{}"),
        Err(ManifestError::Malformed(_))
    ));
}

#[test]
fn rejects_an_unsafe_module_id() {
    let bad = GOOD_MANIFEST.replace("\"code-exec\"", "\"Code_Exec!\"");
    assert!(matches!(
        parse_manifest(bad.as_bytes()),
        Err(ManifestError::Malformed(_))
    ));
}

#[test]
fn rejects_an_unsafe_permission_key() {
    let bad = GOOD_MANIFEST.replace("\"key\": \"run\"", "\"key\": \"Run Now\"");
    assert!(matches!(
        parse_manifest(bad.as_bytes()),
        Err(ManifestError::Malformed(_))
    ));
}

#[test]
fn rejects_a_short_sha256() {
    let bad = GOOD_MANIFEST.replace(
        "0000000000000000000000000000000000000000000000000000000000000000",
        "abc123",
    );
    assert!(matches!(
        parse_manifest(bad.as_bytes()),
        Err(ManifestError::Malformed(_))
    ));
}

#[test]
fn rejects_an_unsupported_schema_version() {
    let bad = GOOD_MANIFEST.replacen("\"schema\": 1,", "\"schema\": 99,", 1);
    assert!(matches!(
        parse_manifest(bad.as_bytes()),
        Err(ManifestError::Malformed(_))
    ));
}

#[test]
fn rejects_a_path_traversal_artifact_path() {
    let bad = GOOD_MANIFEST.replace(
        "\"modules/code-exec/0.1.0/module.wasm\"",
        "\"../../etc/passwd\"",
    );
    assert!(matches!(
        parse_manifest(bad.as_bytes()),
        Err(ManifestError::Malformed(_))
    ));
}

#[test]
fn slug_validator_accepts_only_lowercase_alnum_and_hyphen() {
    assert!(validate_slug("code-exec", 64).is_ok());
    assert!(validate_slug("a1-b2", 64).is_ok());
    assert!(validate_slug("", 64).is_err());
    assert!(validate_slug("Code-Exec", 64).is_err());
    assert!(validate_slug("code_exec", 64).is_err());
    assert!(validate_slug("code exec", 64).is_err());
    assert!(validate_slug(&"a".repeat(65), 64).is_err());
}
