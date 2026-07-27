// SPDX-License-Identifier: AGPL-3.0-only
//! slim-m home server binary. All logic lives in the `slimm_server` library;
//! this only picks which entry point an invocation asked for.

const USAGE: &str = "usage: slimm-server [--healthcheck | import-emoji <directory>]";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        // No arguments is the server itself, which is how the container image
        // runs it: the Dockerfile sets an ENTRYPOINT and no CMD.
        None => slimm_server::run().await,
        // `--healthcheck` is how the distroless container image checks liveness.
        Some("--healthcheck") => slimm_server::healthcheck().await,
        Some("import-emoji") => match args.next() {
            Some(dir) => slimm_server::import_emoji(std::path::Path::new(&dir)).await,
            None => anyhow::bail!("import-emoji needs a directory\n{USAGE}"),
        },
        // Refused rather than ignored: an unrecognised argument silently
        // starting a server is how a typo becomes a no-op nobody notices.
        Some(other) => anyhow::bail!("unknown argument {other:?}\n{USAGE}"),
    }
}
