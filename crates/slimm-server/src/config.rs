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

    /// Most bytes the deployment will hold in stored attachments and custom
    /// emoji together, or `None` for no ceiling.
    ///
    /// `None` is the default because the right number is the operator's disk,
    /// not ours, and a guess would either refuse a legitimate upload on a large
    /// volume or do nothing on a small one. The shipped compose stack sets a
    /// concrete value, the same way it does for `SLIMM_TRUST_PROXY_HOPS`, so a
    /// self-host that follows the guide gets one without having to know it
    /// exists.
    ///
    /// Avatars are deliberately outside it. They live in their own directory,
    /// one file per account overwritten in place, so their total is bounded by
    /// the member count times `AVATAR_MAX_BYTES` and no upload can grow it -
    /// and they are not rows in `attachments`, so the sum this is checked
    /// against cannot see them anyway. Counting them would need a second
    /// mechanism to bound something that is already bounded.
    #[serde(default)]
    pub max_total_attachment_bytes: Option<u64>,

    /// Which third-party GIF search provider this deployment proxies to:
    /// `tenor` or `klipy`, case-insensitively. Unset or empty means no GIF
    /// search at all - empty is read the same as unset because Compose's
    /// `${VAR:-}` interpolation hands the container an empty string rather
    /// than omitting the variable, the same reason `cors_allowed_origins`
    /// treats the two alike - and unrecognized text is a startup error
    /// rather than a silent fallback, the same treatment an unsafe relay
    /// URL scheme gets.
    ///
    /// Both this and `gif_api_key` must be set together, the same two-state
    /// shape push and LiveKit above already use: a self-host with no key for
    /// either provider simply has no GIF search, a fully supported
    /// deployment. The proxy exists so a client's search and every thumbnail
    /// it renders reach the provider through this server rather than
    /// directly, keeping members' own IP addresses away from Tenor or Klipy;
    /// see [`crate::http::gifs`].
    pub gif_provider: Option<String>,
    /// The operator's API key for whichever provider `gif_provider` names.
    pub gif_api_key: Option<String>,

    /// Browser origins allowed to call this deployment cross-origin, comma
    /// separated, for example `https://app.example.com,http://localhost:8099`.
    ///
    /// Unset or empty means no CORS layer at all, and a browser on any other
    /// origin is refused. Native clients send no `Origin` and are unaffected,
    /// so only a web build of the client needs this; see [`crate::cors`] for
    /// why that default is the safe one.
    pub cors_allowed_origins: Option<String>,

    /// How many reverse proxies in front of this server may be believed about
    /// who an unauthenticated caller is, for rate limiting.
    ///
    /// Zero, the default, believes none of them and keys on the TCP peer, which
    /// is the only safe answer for a directly-exposed server: `X-Forwarded-For`
    /// is unsigned and anyone may send one.
    ///
    /// Set it to the number of proxies you actually run - 1 behind the Caddy in
    /// `deploy/` - and the address that many places from the right of that
    /// header is used instead. Counting from the right is what makes it safe;
    /// see `http::extract::limit_key`.
    ///
    /// Getting it wrong is not equally bad in both directions. Too low keys
    /// every unauthenticated caller together, so one of them can hold a bucket
    /// empty for everybody. Too high reads an address the client chose, so each
    /// caller can mint unlimited buckets. Neither is silent in the logs, but
    /// only the second is a bypass, which is why the default is zero.
    #[serde(default)]
    pub trust_proxy_hops: usize,
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

/// 100 MiB, four times Discord's free 25 MiB. Safe as a default because a
/// self-hosted operator owns the disk, can bound total use with
/// `SLIMM_MAX_TOTAL_ATTACHMENT_BYTES`, and can lower this per instance.
fn default_attachment_max_bytes() -> u64 {
    100 * 1024 * 1024
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
            max_total_attachment_bytes: None,
            gif_provider: None,
            gif_api_key: None,
            cors_allowed_origins: None,
            trust_proxy_hops: 0,
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
        assert_eq!(from_empty_env.gif_provider, defaulted.gif_provider);
        assert_eq!(from_empty_env.gif_api_key, defaulted.gif_api_key);
        assert_eq!(
            from_empty_env.cors_allowed_origins,
            defaulted.cors_allowed_origins
        );
    }

    /// An unset origin list and an explicitly empty one must be the same
    /// thing, because `SLIMM_CORS_ALLOWED_ORIGINS=` in a compose file is how
    /// an operator turns the browser surface back off.
    #[test]
    fn an_empty_origin_list_is_read_as_an_empty_string_not_dropped() {
        let env =
            std::collections::HashMap::from([("CORS_ALLOWED_ORIGINS".to_owned(), String::new())]);
        let config: Config = envy::from_iter(env).expect("all other fields have defaults");
        assert_eq!(config.cors_allowed_origins.as_deref(), Some(""));
    }
}
