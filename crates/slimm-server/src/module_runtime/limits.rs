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

/// The most memory a manifest may ask for. A manifest's `runtime.limits` is
/// the module's declared ceiling, but the host is the one paying for it, so
/// each limit also has a host-side maximum a manifest cannot exceed - without
/// one, a manifest claiming gigabytes or hours would be honoured verbatim.
/// 256 MiB is far above any pure-compute module's needs while still small
/// against a self-host's total memory.
pub const MAX_MEMORY_MB: u64 = 256;
/// The longest wall-clock cap a manifest may declare. A command is a
/// request-response call the caller waits on, so ten seconds is already long.
pub const MAX_WALL_MS: u64 = 10_000;
/// The largest fuel budget a manifest may declare, forty times the default:
/// the blocking task is not killed at the wall-clock deadline, only abandoned,
/// so fuel is what actually ends a runaway run and must stay bounded too.
pub const MAX_FUEL: u64 = 2_000_000_000;

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
