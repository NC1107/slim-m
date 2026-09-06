// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! [`ModuleHost`] against hand-written WAT, compiled to wasm at test time so
//! each fixture's exact behavior - an infinite loop, a declared import, an
//! oversized memory - is readable right here rather than shipped as an
//! opaque checked-in binary.

use std::time::Duration;

use super::{ModuleHost, RunError, RunLimits};

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

fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    crate::media::to_hex(&Sha256::digest(bytes))
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
