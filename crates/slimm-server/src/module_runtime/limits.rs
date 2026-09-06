// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Resource limits [`super::ModuleHost::run`] enforces, and the defaults a
//! manifest that leaves one unset falls back to.

use std::time::Duration;

use crate::store::ModuleRuntimeLimits;

/// Applied when a manifest's `runtime.limits` leaves memory unset: 16 MiB is
/// comfortably inside a self-host's memory budget even with several modules
/// installed, and far above what a pure-compute module needs per call.
const DEFAULT_MEMORY_MB: u64 = 16;
/// Applied when a manifest leaves the wall-clock cap unset. A command is a
/// synchronous request-response call, not a background job, so a second is
/// already generous for the caller waiting on it.
const DEFAULT_WALL_MS: u64 = 1_000;
/// Applied when a manifest leaves fuel unset. wasmi charges roughly one unit
/// of fuel per executed instruction, so this bounds a run to tens of millions
/// of instructions - enough for real work, far short of a runaway loop
/// running forever.
const DEFAULT_FUEL: u64 = 50_000_000;

/// The concrete caps one `run` call is held to, resolved from a manifest's
/// (possibly partial) `runtime.limits` against the defaults above.
#[derive(Debug, Clone, Copy)]
pub struct RunLimits {
    pub memory_bytes: usize,
    pub fuel: u64,
    pub wall: Duration,
}

impl From<&ModuleRuntimeLimits> for RunLimits {
    fn from(limits: &ModuleRuntimeLimits) -> Self {
        let memory_mb = limits.memory_mb.unwrap_or(DEFAULT_MEMORY_MB);
        Self {
            memory_bytes: (memory_mb.saturating_mul(1024 * 1024)) as usize,
            fuel: limits.fuel.unwrap_or(DEFAULT_FUEL),
            wall: Duration::from_millis(limits.wall_ms.unwrap_or(DEFAULT_WALL_MS)),
        }
    }
}
