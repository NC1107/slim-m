// SPDX-License-Identifier: AGPL-3.0-only
//! Runtime configuration, loaded from `SLIMM_`-prefixed environment variables.
//!
//! Flat environment-variable config keeps the self-host operational surface
//! minimal: a single Docker Compose deployment sets a handful of variables and
//! nothing more.

use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    /// TCP port the HTTP and WebSocket surface binds to.
    #[serde(default = "default_port")]
    pub port: u16,

    /// Filesystem path to the embedded SQLite database file.
    #[serde(default = "default_database_path")]
    pub database_path: String,

    /// How many Argon2id password hashes may run at once. Each costs ~19 MiB, so
    /// this caps the transient memory a burst of logins can claim; requests over
    /// the limit wait on the semaphore rather than piling that memory up.
    #[serde(default = "default_hash_concurrency")]
    pub hash_concurrency: usize,

    /// Base URL of the push relay (for example `https://relay.example.com`);
    /// `/v1/send` is appended when calling it.
    pub push_relay_url: Option<String>,
    /// Bearer key this deployment authenticates to the relay with.
    ///
    /// Both push settings are optional together: a LAN-only or
    /// NAT-unreachable self-host has nowhere for a relay to reach it, and
    /// running with push disabled is a supported first-class configuration,
    /// not an error.
    pub push_relay_key: Option<String>,
}

fn default_port() -> u16 {
    8080
}

fn default_database_path() -> String {
    "data/slimm.db".to_owned()
}

fn default_hash_concurrency() -> usize {
    4
}

impl Config {
    /// Reads configuration from `SLIMM_`-prefixed environment variables,
    /// for example `SLIMM_PORT` and `SLIMM_DATABASE_PATH`.
    pub fn from_env() -> anyhow::Result<Self> {
        let config = envy::prefixed("SLIMM_").from_env::<Config>()?;
        Ok(config)
    }
}
