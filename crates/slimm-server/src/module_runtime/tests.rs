// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! [`ModuleHost`] against hand-written WAT, compiled to wasm at test time so
//! each fixture's exact behavior - an infinite loop, a declared import, an
//! oversized memory - is readable right here rather than shipped as an
//! opaque checked-in binary.

use std::sync::Arc;
use std::time::Duration;

use super::{CapabilitySurface, InMemoryKv, ModuleHost, RunError, RunLimits};

const GENEROUS: RunLimits = RunLimits {
    memory_bytes: 4 * 1024 * 1024,
    fuel: 50_000_000,
    wall: Duration::from_millis(500),
};

fn wat(text: &str) -> Vec<u8> {
    wat::parse_str(text).expect("fixture WAT must parse")
}

/// A bump allocator plus a `run` that ASCII-uppercases its input in place and
/// returns the same region back - proves the alloc/write/call/read plumbing
/// end to end without any JSON logic in the fixture itself.
fn echo_upper_wasm() -> Vec<u8> {
    wat(r#"
        (module
            (memory (export "memory") 1)
            (global $bump (mut i32) (i32.const 1024))
            (func (export "alloc") (param $len i32) (result i32)
                (local $ptr i32)
                (local.set $ptr (global.get $bump))
                (global.set $bump (i32.add (global.get $bump) (local.get $len)))
                (local.get $ptr))
            (func (export "run") (param $in_ptr i32) (param $in_len i32) (result i64)
                (local $i i32)
                (local $b i32)
                (block $done
                    (loop $loop
                        (br_if $done (i32.ge_u (local.get $i) (local.get $in_len)))
                        (local.set $b (i32.load8_u (i32.add (local.get $in_ptr) (local.get $i))))
                        (if (i32.and
                                (i32.ge_u (local.get $b) (i32.const 97))
                                (i32.le_u (local.get $b) (i32.const 122)))
                            (then (local.set $b (i32.sub (local.get $b) (i32.const 32)))))
                        (i32.store8 (i32.add (local.get $in_ptr) (local.get $i)) (local.get $b))
                        (local.set $i (i32.add (local.get $i) (i32.const 1)))
                        (br $loop)))
                (i64.or
                    (i64.shl (i64.extend_i32_u (local.get $in_ptr)) (i64.const 32))
                    (i64.extend_i32_u (local.get $in_len)))))
    "#)
}

/// Otherwise ABI-conformant, but declares a wasm import - the one shape the
/// host must refuse outright, per the module ABI's "no ambient authority"
/// rule.
fn importing_wasm() -> Vec<u8> {
    wat(r#"
        (module
            (import "env" "log" (func $log (param i32)))
            (memory (export "memory") 1)
            (func (export "alloc") (param $len i32) (result i32) (i32.const 0))
            (func (export "run") (param $in_ptr i32) (param $in_len i32) (result i64) (i64.const 0)))
    "#)
}

/// `run` never returns: an unconditional loop back to its own start, burning
/// fuel forever.
fn fuel_burner_wasm() -> Vec<u8> {
    wat(r#"
        (module
            (memory (export "memory") 1)
            (func (export "alloc") (param $len i32) (result i32) (i32.const 0))
            (func (export "run") (param $in_ptr i32) (param $in_len i32) (result i64)
                (loop $l (br $l))
                (i64.const 0)))
    "#)
}

/// Declares a minimum memory of 2 pages (128 KiB), deliberately larger than
/// the 1-page cap the memory-cap test configures, so instantiation itself is
/// refused before `run` is ever reachable.
fn memory_hog_wasm() -> Vec<u8> {
    wat(r#"
        (module
            (memory (export "memory") 2)
            (func (export "alloc") (param $len i32) (result i32) (i32.const 0))
            (func (export "run") (param $in_ptr i32) (param $in_len i32) (result i64) (i64.const 0)))
    "#)
}

/// ABI-conformant and declares the single `slim.host_call` import (the only
/// import a capability-using module may have): a bump allocator so the host can
/// write the response back, the `request` staged at offset 1024, and a `run`
/// that calls `host_call` on it and returns its packed result verbatim - so the
/// host's response comes straight back out as the module's output.
fn host_call_wasm(request: &str) -> Vec<u8> {
    let escaped: String = request
        .chars()
        .flat_map(|c| match c {
            '"' => vec!['\\', '"'],
            '\\' => vec!['\\', '\\'],
            other => vec![other],
        })
        .collect();
    wat(&format!(
        r#"
        (module
            (import "slim" "host_call" (func $host_call (param i32 i32) (result i64)))
            (memory (export "memory") 1)
            (global $bump (mut i32) (i32.const 8192))
            (data (i32.const 1024) "{escaped}")
            (func (export "alloc") (param $len i32) (result i32)
                (local $ptr i32)
                (local.set $ptr (global.get $bump))
                (global.set $bump (i32.add (global.get $bump) (local.get $len)))
                (local.get $ptr))
            (func (export "run") (param $in_ptr i32) (param $in_len i32) (result i64)
                (call $host_call (i32.const 1024) (i32.const {len}))))
        "#,
        len = request.len()
    ))
}

fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    crate::media::to_hex(&Sha256::digest(bytes))
}

/// The surface is off on every live path, so a module importing `host_call` is
/// refused exactly like any other import - a stock deployment is unchanged.
#[tokio::test]
async fn a_host_call_module_is_refused_when_the_surface_is_off() {
    let wasm = host_call_wasm(r#"{"capability":"kv.store"}"#);
    let sha256 = sha256_hex(&wasm);

    let err = ModuleHost::run(wasm, sha256, GENEROUS, b"hi".to_vec())
        .await
        .expect_err("host_call must be refused while the surface is off");

    assert!(matches!(err, RunError::ImportsNotAllowed));
}

/// With the surface on and a capability approved, the `host_call` import links
/// (the module instantiates and runs), and an approved capability the host does
/// not implement comes back a clean refusal rather than a trap.
#[tokio::test]
async fn an_enabled_host_call_instantiates_and_an_unimplemented_capability_is_refused() {
    let wasm = host_call_wasm(r#"{"capability":"message.post","text":"hi"}"#);
    let sha256 = sha256_hex(&wasm);
    let surface = CapabilitySurface::enabled(
        vec!["message.post".to_owned()],
        "test-module",
        Arc::new(InMemoryKv::default()),
    );

    let output = ModuleHost::run_with_capabilities(wasm, sha256, GENEROUS, b"hi".to_vec(), surface)
        .await
        .expect("the module should instantiate and its host_call should answer");

    let text = String::from_utf8(output).expect("the response is UTF-8 JSON");
    assert!(text.contains(r#""ok":false"#), "{text}");
    assert!(text.contains("not available: message.post"), "{text}");
}

/// The `kv.store` capability, end to end through the real wasm `host_call`: a
/// `set` in one run is readable by a `get` in a later run sharing the same
/// backend - the whole path (import, memory read, gate, kv, alloc-and-write
/// back) works, and the capability persists across runs.
#[tokio::test]
async fn kv_store_round_trips_across_runs_through_host_call() {
    let kv = Arc::new(InMemoryKv::default());

    let set = host_call_wasm(r#"{"capability":"kv.store","op":"set","key":"score","value":"42"}"#);
    let out = ModuleHost::run_with_capabilities(
        set.clone(),
        sha256_hex(&set),
        GENEROUS,
        b"hi".to_vec(),
        CapabilitySurface::enabled(vec!["kv.store".to_owned()], "game", kv.clone()),
    )
    .await
    .expect("set should run");
    assert!(String::from_utf8(out).unwrap().contains(r#""ok":true"#));

    let get = host_call_wasm(r#"{"capability":"kv.store","op":"get","key":"score"}"#);
    let out = ModuleHost::run_with_capabilities(
        get.clone(),
        sha256_hex(&get),
        GENEROUS,
        b"hi".to_vec(),
        CapabilitySurface::enabled(vec!["kv.store".to_owned()], "game", kv.clone()),
    )
    .await
    .expect("get should run");
    assert!(String::from_utf8(out).unwrap().contains(r#""value":"42""#));
}

/// The surface being on is not enough: with no capability approved for the
/// module, even the `host_call` import is refused.
#[tokio::test]
async fn an_enabled_surface_with_no_approved_capability_refuses_the_import() {
    let wasm = host_call_wasm(r#"{"capability":"kv.store"}"#);
    let sha256 = sha256_hex(&wasm);
    let surface = CapabilitySurface::enabled(vec![], "m", Arc::new(InMemoryKv::default()));

    let err = ModuleHost::run_with_capabilities(wasm, sha256, GENEROUS, b"hi".to_vec(), surface)
        .await
        .expect_err("no approved capability means no host_call import");

    assert!(matches!(err, RunError::ImportsNotAllowed));
}

/// Only `slim.host_call` is ever allowed: any other import is refused even with
/// the surface on and a capability approved.
#[tokio::test]
async fn any_other_import_is_refused_even_with_the_surface_on() {
    let wasm = importing_wasm(); // imports env.log
    let sha256 = sha256_hex(&wasm);
    let surface = CapabilitySurface::enabled(
        vec!["kv.store".to_owned()],
        "m",
        Arc::new(InMemoryKv::default()),
    );

    let err = ModuleHost::run_with_capabilities(wasm, sha256, GENEROUS, b"hi".to_vec(), surface)
        .await
        .expect_err("only slim.host_call may be imported");

    assert!(matches!(err, RunError::ImportsNotAllowed));
}

#[tokio::test]
async fn run_returns_the_modules_own_output() {
    let wasm = echo_upper_wasm();
    let sha256 = sha256_hex(&wasm);

    let output = ModuleHost::run(wasm, sha256, GENEROUS, b"hello there".to_vec())
        .await
        .expect("a conforming module should run");

    assert_eq!(output, b"HELLO THERE");
}

#[tokio::test]
async fn a_module_that_imports_anything_is_refused() {
    let wasm = importing_wasm();
    let sha256 = sha256_hex(&wasm);

    let err = ModuleHost::run(wasm, sha256, GENEROUS, b"hi".to_vec())
        .await
        .expect_err("a module with an import must be refused");

    assert!(matches!(err, RunError::ImportsNotAllowed));
}

#[tokio::test]
async fn a_hash_mismatch_is_refused_before_anything_runs() {
    let wasm = echo_upper_wasm();

    let err = ModuleHost::run(wasm, "0".repeat(64), GENEROUS, b"hi".to_vec())
        .await
        .expect_err("a wrong sha256 must be refused");

    assert!(matches!(err, RunError::HashMismatch));
}

#[tokio::test]
async fn a_fuel_exhausting_module_is_killed_with_a_clean_error() {
    let wasm = fuel_burner_wasm();
    let sha256 = sha256_hex(&wasm);
    let tight_fuel = RunLimits {
        fuel: 10_000,
        ..GENEROUS
    };

    let err = ModuleHost::run(wasm, sha256, tight_fuel, b"hi".to_vec())
        .await
        .expect_err("an infinite loop must not hang the caller");

    assert!(matches!(err, RunError::ResourceLimited(_)));
}

#[tokio::test]
async fn a_module_over_the_memory_cap_is_refused() {
    let wasm = memory_hog_wasm();
    let sha256 = sha256_hex(&wasm);
    let tiny_memory = RunLimits {
        memory_bytes: 64 * 1024,
        ..GENEROUS
    };

    let err = ModuleHost::run(wasm, sha256, tiny_memory, b"hi".to_vec())
        .await
        .expect_err("a module declaring more memory than the cap must be refused");

    assert!(matches!(err, RunError::Instantiate(_)));
}

/// A backstop below the fuel cap: even if fuel metering did not exist, the
/// wall-clock timeout alone must still return promptly rather than hang.
#[tokio::test]
async fn a_fuel_exhausting_module_still_returns_promptly_under_a_short_wall_clock() {
    let wasm = fuel_burner_wasm();
    let sha256 = sha256_hex(&wasm);
    let short_wall = RunLimits {
        wall: Duration::from_millis(200),
        ..GENEROUS
    };

    let started = std::time::Instant::now();
    let err = ModuleHost::run(wasm, sha256, short_wall, b"hi".to_vec())
        .await
        .expect_err("a runaway module must not hang the caller");
    assert!(started.elapsed() < Duration::from_secs(2));
    assert!(matches!(
        err,
        RunError::ResourceLimited(_) | RunError::Timeout
    ));
}
