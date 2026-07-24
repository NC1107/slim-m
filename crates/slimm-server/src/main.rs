// SPDX-License-Identifier: AGPL-3.0-only
//! slim-m home server binary. All logic lives in the `slimm_server` library.

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // `--healthcheck` is how the distroless container image checks liveness.
    if std::env::args().nth(1).as_deref() == Some("--healthcheck") {
        return slimm_server::healthcheck().await;
    }
    slimm_server::run().await
}
