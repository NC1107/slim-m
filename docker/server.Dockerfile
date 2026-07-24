# SPDX-License-Identifier: AGPL-3.0-only
# Production image for the slim-m home server.
#
# Two stages: a static musl build, then a distroless nonroot runtime. The final
# image ships one static binary plus a nonroot-owned /data directory for the
# embedded SQLite database, and uses the binary's own --healthcheck subcommand
# since distroless has no shell.
#
# Multi-arch: this Dockerfile builds natively for whatever platform it is invoked
# with (buildx pulls the matching target-arch base image), so `--platform
# linux/arm64` produces a real arm64 binary. Release builds one image per
# architecture on a native runner and merges them into one manifest (see
# .github/workflows/release.yml), so there is no slow QEMU cross-compilation and
# no cross-linking toolchain to maintain.

FROM rust:1-alpine AS builder
RUN apk add --no-cache musl-dev
WORKDIR /build
COPY . .
RUN cargo build --release --bin slimm-server \
    && mkdir -p /out/data \
    && cp target/release/slimm-server /out/slimm-server

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=builder /out/slimm-server /usr/local/bin/slimm-server
COPY --from=builder --chown=nonroot:nonroot /out/data /data

ENV SLIMM_PORT=8080 \
    SLIMM_DATABASE_PATH=/data/slimm.db
EXPOSE 8080
VOLUME ["/data"]
USER nonroot

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/usr/local/bin/slimm-server", "--healthcheck"]

ENTRYPOINT ["/usr/local/bin/slimm-server"]
