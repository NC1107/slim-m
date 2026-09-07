// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! The one wasmi [`Engine`] every run shares, and a content-addressed cache of
//! compiled [`Module`]s in front of it.
//!
//! Compiling a module (parse, validate, translate) is the expensive part of a
//! run and is a pure function of the artifact bytes; the host has already
//! proved those bytes match the sha256 recorded at install before it gets
//! here. Keying the cache by that verified digest therefore changes nothing a
//! module can observe: a fresh `Store` and `Instance` are still built per run,
//! so no memory, globals, or fuel ever carry over between calls. Only the
//! translation work is reused.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use wasmi::{Config, Engine, Module};

use super::host::RunError;

/// How many distinct artifacts stay compiled at once. A deployment installs a
/// handful of modules, so this is well above steady state; when it is
/// exceeded the whole cache is dropped rather than tracking recency, since a
/// miss only costs one recompile.
const MAX_CACHED_MODULES: usize = 16;

fn engine() -> &'static Engine {
    static ENGINE: OnceLock<Engine> = OnceLock::new();
    ENGINE.get_or_init(|| {
        let mut config = Config::default();
        config.consume_fuel(true);
        Engine::new(&config)
    })
}

fn cache() -> &'static Mutex<HashMap<String, Module>> {
    static CACHE: OnceLock<Mutex<HashMap<String, Module>>> = OnceLock::new();
    CACHE.get_or_init(Mutex::default)
}

/// The compiled form of `wasm`, whose verified sha256 is `sha256`, compiling
/// it on the first sight of that digest and reusing it after.
pub(super) fn compiled_module(sha256: &str, wasm: &[u8]) -> Result<Module, RunError> {
    if let Some(module) = cache().lock().ok().and_then(|c| c.get(sha256).cloned()) {
        return Ok(module);
    }
    let module = Module::new(engine(), wasm)
        .map_err(|e| RunError::Instantiate(format!("invalid wasm module: {e}")))?;
    if let Ok(mut cache) = cache().lock() {
        if cache.len() >= MAX_CACHED_MODULES {
            cache.clear();
        }
        cache.insert(sha256.to_owned(), module.clone());
    }
    Ok(module)
}

/// The engine a compiled module belongs to; a run's `Store` must be built on
/// the same one.
pub(super) fn shared_engine() -> &'static Engine {
    engine()
}

#[cfg(test)]
pub(super) fn is_cached(sha256: &str) -> bool {
    cache()
        .lock()
        .map(|c| c.contains_key(sha256))
        .unwrap_or(false)
}
