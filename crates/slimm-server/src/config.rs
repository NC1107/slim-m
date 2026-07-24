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
}

fn default_port() -> u16 {
    8080
}

fn default_database_path() -> String {
    "data/slimm.db".to_owned()
}

impl Config {
    /// Reads configuration from `SLIMM_`-prefixed environment variables,
    /// for example `SLIMM_PORT` and `SLIMM_DATABASE_PATH`.
    pub fn from_env() -> anyhow::Result<Self> {
        let config = envy::prefixed("SLIMM_").from_env::<Config>()?;
        Ok(config)
    }
}
