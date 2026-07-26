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

    /// The LiveKit SFU clients connect to, for example
    /// `wss://livekit.example.com`. Handed to the client alongside a token,
    /// so it is the address reachable from outside, not the compose-internal
    /// one.
    pub livekit_url: Option<String>,
    /// API key the SFU knows this deployment by.
    pub livekit_api_key: Option<String>,
    /// The matching secret, which room tokens are signed with.
    ///
    /// All three LiveKit settings are optional together, and a deployment
    /// without them simply has no voice: the same first-class two-state shape
    /// as push above, because a text-only self-host is a supported way to run
    /// this and should not need to stand up an SFU to start.
    pub livekit_api_secret: Option<String>,

    /// Directory attachment and avatar bytes are stored under, beside the
    /// database rather than in it. A sibling of the database's own default
    /// (`data/slimm.db`), so a local `cargo run` gets both without any
    /// configuration, and the container image overrides both to absolute
    /// paths under the same mounted volume (see `docker/server.Dockerfile`).
    #[serde(default = "default_attachments_dir")]
    pub attachments_dir: String,

    /// Largest attachment a single upload may store, in bytes.
    #[serde(default = "default_attachment_max_bytes")]
    pub attachment_max_bytes: u64,
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

fn default_attachments_dir() -> String {
    "data/media".to_owned()
}

fn default_attachment_max_bytes() -> u64 {
    10 * 1024 * 1024
}

impl Default for Config {
    fn default() -> Self {
        Self {
            port: default_port(),
            database_path: default_database_path(),
            hash_concurrency: default_hash_concurrency(),
            push_relay_url: None,
            push_relay_key: None,
            livekit_url: None,
            livekit_api_key: None,
            livekit_api_secret: None,
            attachments_dir: default_attachments_dir(),
            attachment_max_bytes: default_attachment_max_bytes(),
        }
    }
}

impl Config {
    /// Reads configuration from `SLIMM_`-prefixed environment variables,
    /// for example `SLIMM_PORT` and `SLIMM_DATABASE_PATH`.
    pub fn from_env() -> anyhow::Result<Self> {
        let config = envy::prefixed("SLIMM_").from_env::<Config>()?;
        Ok(config)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `Default` reuses the same `default_*` functions serde calls when a
    /// field is missing from the environment, but nothing stops the two from
    /// drifting apart if a future edit changes one and not the other. This
    /// deserializes an empty environment map through the same `Deserialize`
    /// impl `from_env` uses and checks it lands on exactly what `Default`
    /// produces, so that drift fails a test instead of shipping silently.
    #[test]
    fn default_matches_deserializing_an_empty_config() {
        let empty: std::collections::HashMap<String, String> = std::collections::HashMap::new();
        let from_empty_env: Config = envy::from_iter(empty).expect("all fields have defaults");
        let defaulted = Config::default();

        assert_eq!(from_empty_env.port, defaulted.port);
        assert_eq!(from_empty_env.database_path, defaulted.database_path);
        assert_eq!(from_empty_env.hash_concurrency, defaulted.hash_concurrency);
        assert_eq!(from_empty_env.push_relay_url, defaulted.push_relay_url);
        assert_eq!(from_empty_env.push_relay_key, defaulted.push_relay_key);
        assert_eq!(from_empty_env.livekit_url, defaulted.livekit_url);
        assert_eq!(from_empty_env.livekit_api_key, defaulted.livekit_api_key);
        assert_eq!(
            from_empty_env.livekit_api_secret,
            defaulted.livekit_api_secret
        );
        assert_eq!(from_empty_env.attachments_dir, defaulted.attachments_dir);
        assert_eq!(
            from_empty_env.attachment_max_bytes,
            defaulted.attachment_max_bytes
        );
    }
}
