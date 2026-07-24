// SPDX-License-Identifier: AGPL-3.0-only
//! Phase 0 hot-path benchmarks.
//!
//! `slimm-server` exposes only a binary target, not a library, so this file
//! cannot import its internal modules. Each benchmark instead re-creates the
//! relevant hot path from the same public crates the server uses, which
//! keeps the file self-contained while still measuring real Phase 0 costs:
//! generating a UUIDv7 event identity, and serializing the `/version`
//! response body.

use criterion::{Criterion, black_box, criterion_group, criterion_main};
use serde::Serialize;

/// Mirrors the response shape served by `GET /version` in `src/main.rs`.
#[derive(Serialize)]
struct Version {
    name: &'static str,
    version: &'static str,
    protocol: u32,
}

/// Every stored message and event gets a UUIDv7 identity, so its generation
/// cost sits on the write path of every mutation the server accepts.
fn bench_uuid_v7(c: &mut Criterion) {
    c.bench_function("uuid_now_v7", |b| {
        b.iter(|| black_box(uuid::Uuid::now_v7()));
    });
}

/// `/version` is served on every client handshake, so its serialization
/// cost, however small, runs on the connection-setup path.
fn bench_version_json(c: &mut Criterion) {
    let body = Version {
        name: "slim-m",
        version: env!("CARGO_PKG_VERSION"),
        protocol: 1,
    };

    c.bench_function("version_json_serialize", |b| {
        b.iter(|| {
            black_box(serde_json::to_vec(black_box(&body)).expect("serialize /version body"))
        });
    });
}

criterion_group!(hot_paths, bench_uuid_v7, bench_version_json);
criterion_main!(hot_paths);
