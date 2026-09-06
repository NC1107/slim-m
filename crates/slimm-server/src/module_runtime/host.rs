// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! [`ModuleHost`]: the wasmi instantiation and call sequence behind
//! [`super`]'s ABI, and every way it can fail cleanly instead of hanging or
//! panicking the caller.

use std::fmt;

use sha2::{Digest, Sha256};
use wasmi::core::TrapCode;
use wasmi::{Config, Engine, Instance, Module, Store as WasmiStore, StoreLimitsBuilder};

use super::limits::RunLimits;
use crate::media::to_hex;

/// Why a run did not produce the module's own response bytes. Every variant
/// is a clean, typed outcome - `http::module_commands` turns each into an
/// `{ "ok": false, "error": ... }` body, never a 500 and never a hang.
#[derive(Debug)]
pub enum RunError {
    /// The stored artifact's sha256 no longer matches what was recorded at
    /// install time.
    HashMismatch,
    /// The module declares at least one wasm import. Per the ABI (see
    /// `super`'s module doc), a v1 module may only compute; the host refuses
    /// to instantiate anything that asks for a host function, memory import,
    /// or anything else.
    ImportsNotAllowed,
    /// The wasm bytes did not parse, did not instantiate, or did not export
    /// the ABI's `memory`, `alloc`, and `run`.
    Instantiate(String),
    /// `alloc` or `run` trapped for a reason other than a resource limit
    /// (an out-of-bounds access, an integer overflow, an explicit
    /// `unreachable`, and so on).
    Trap(String),
    /// The module ran into its fuel or memory ceiling.
    ResourceLimited(String),
    /// The wall-clock cap elapsed before `run` returned.
    Timeout,
}

impl fmt::Display for RunError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            RunError::HashMismatch => write!(f, "module artifact failed integrity verification"),
            RunError::ImportsNotAllowed => {
                write!(f, "module declares an import, which v1 modules may not do")
            }
            RunError::Instantiate(detail) => write!(f, "module failed to load: {detail}"),
            RunError::Trap(detail) => write!(f, "module trapped: {detail}"),
            RunError::ResourceLimited(detail) => write!(f, "module exceeded its limits: {detail}"),
            RunError::Timeout => write!(f, "module timed out"),
        }
    }
}

/// The Phase 3 module host: given a module's own wasm bytes, runs its `run`
/// export against one request under the caller-supplied [`RunLimits`]. See
/// [`super`]'s module doc for the wire ABI this assumes.
pub struct ModuleHost;

impl ModuleHost {
    /// Verifies `wasm`'s sha256 against `expected_sha256`, then instantiates
    /// and calls it on a blocking task bounded by `limits.wall`: wasmi has no
    /// way to preempt a running interpreter loop from outside, so a module
    /// that somehow outruns its fuel budget (or one configured with an
    /// unreasonably large one) is abandoned at the wall-clock deadline rather
    /// than left to block the caller. The blocking task itself is not
    /// killed - only fuel exhaustion or completion ends it - but the fuel
    /// cap is sized so that in practice it always ends first; the timeout is
    /// the backstop that keeps a caller from ever waiting past it.
    pub async fn run(
        wasm: Vec<u8>,
        expected_sha256: String,
        limits: RunLimits,
        input: Vec<u8>,
    ) -> Result<Vec<u8>, RunError> {
        let digest = to_hex(&Sha256::digest(&wasm));
        if digest != expected_sha256 {
            return Err(RunError::HashMismatch);
        }

        let wall = limits.wall;
        let task = tokio::task::spawn_blocking(move || run_sync(&wasm, limits, &input));
        match tokio::time::timeout(wall, task).await {
            Ok(Ok(result)) => result,
            Ok(Err(_join_error)) => Err(RunError::Trap("module task did not complete".to_owned())),
            Err(_elapsed) => Err(RunError::Timeout),
        }
    }
}

fn run_sync(wasm: &[u8], limits: RunLimits, input: &[u8]) -> Result<Vec<u8>, RunError> {
    let mut config = Config::default();
    config.consume_fuel(true);
    let engine = Engine::new(&config);

    let module = Module::new(&engine, wasm)
        .map_err(|e| RunError::Instantiate(format!("invalid wasm module: {e}")))?;
    if module.imports().next().is_some() {
        return Err(RunError::ImportsNotAllowed);
    }

    let store_limits = StoreLimitsBuilder::new()
        .memory_size(limits.memory_bytes)
        .build();
    let mut store = WasmiStore::new(&engine, store_limits);
    store.limiter(|limits| limits);
    store
        .set_fuel(limits.fuel)
        .map_err(|e| RunError::Instantiate(format!("failed to configure fuel: {e}")))?;

    let instance = Instance::new(&mut store, &module, &[])
        .map_err(|e| RunError::Instantiate(format!("module failed to instantiate: {e}")))?;

    let memory = instance.get_memory(&store, "memory").ok_or_else(|| {
        RunError::Instantiate("module does not export a memory named \"memory\"".to_owned())
    })?;
    let alloc = instance
        .get_typed_func::<i32, i32>(&store, "alloc")
        .map_err(|e| RunError::Instantiate(format!("module does not export alloc: {e}")))?;
    let run = instance
        .get_typed_func::<(i32, i32), i64>(&store, "run")
        .map_err(|e| RunError::Instantiate(format!("module does not export run: {e}")))?;

    let in_len = i32::try_from(input.len())
        .map_err(|_| RunError::Instantiate("request too large for a wasm module".to_owned()))?;
    let in_ptr = alloc.call(&mut store, in_len).map_err(classify_trap)?;
    memory
        .write(&mut store, in_ptr as usize, input)
        .map_err(|e| RunError::Instantiate(format!("module's alloc returned bad memory: {e}")))?;

    let packed = run
        .call(&mut store, (in_ptr, in_len))
        .map_err(classify_trap)?;
    let out_ptr = (packed >> 32) as u32 as usize;
    let out_len = (packed & 0xffff_ffff) as u32 as usize;

    let mut output = vec![0u8; out_len];
    memory
        .read(&store, out_ptr, &mut output)
        .map_err(|e| RunError::Instantiate(format!("module's run returned bad memory: {e}")))?;
    Ok(output)
}

/// Fuel exhaustion and a limiter-denied memory growth both surface as a
/// [`TrapCode`], so both map to [`RunError::ResourceLimited`]; every other
/// trap (an out-of-bounds access, an explicit unreachable, and so on) is the
/// module's own bug, not a limit, and maps to [`RunError::Trap`].
fn classify_trap(err: wasmi::Error) -> RunError {
    match err.as_trap_code() {
        Some(TrapCode::OutOfFuel) => {
            RunError::ResourceLimited("exceeded its fuel (CPU) budget".to_owned())
        }
        Some(TrapCode::GrowthOperationLimited) => {
            RunError::ResourceLimited("exceeded its memory budget".to_owned())
        }
        Some(code) => RunError::Trap(format!("{code:?}")),
        None => RunError::Trap(err.to_string()),
    }
}
