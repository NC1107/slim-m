// SPDX-License-Identifier: AGPL-3.0-only
//! Temp directories, temp databases and the byte-level fixtures the import
//! tests are built from.
//!
//! No emoji content is committed here or anywhere else in this repository.
//! Every image below is a magic-number prefix and a few bytes of filler,
//! written into a temp directory by the test itself.

use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};
use slimm_server::config::Config;
use slimm_server::db;
use slimm_server::emoji::import::{Outcome, Report};
use slimm_server::media::Media;
use slimm_server::store::Store;
use uuid::Uuid;

// --- Fixtures ---

pub async fn new_store() -> Store {
    let path = std::env::temp_dir()
        .join(format!("slimm-emoji-import-test-{}.db", Uuid::now_v7()))
        .to_string_lossy()
        .into_owned();
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");
    Store::new(pool)
}

pub fn media_for_test() -> Media {
    media_with_blobs().0
}

/// A media handle plus the directory its blobs land in, for the tests that
/// count files rather than reading one back by hash.
pub fn media_with_blobs() -> (Media, PathBuf) {
    let root = std::env::temp_dir().join(format!("slimm-emoji-media-{}", Uuid::now_v7()));
    let media = Media::new(&root, 10 * 1024 * 1024).expect("create temp media directories");
    (media, root.join("attachments"))
}

/// Every blob written so far. Content-addressed, so one entry is one distinct
/// image, whether an emoji ended up pointing at it or not.
pub fn blobs(dir: &Path) -> Vec<String> {
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .expect("read the blob directory")
        .map(|entry| {
            entry
                .expect("a blob entry")
                .file_name()
                .to_string_lossy()
                .into_owned()
        })
        .collect();
    names.sort();
    names
}

/// Whether these bytes left anything behind: the blob on disk and the
/// `attachments` row that points at it.
pub async fn stored(store: &Store, blob_dir: &Path, bytes: &[u8]) -> (bool, bool) {
    let sha = Sha256::digest(bytes).to_vec();
    let row = store
        .attachment_summary(&sha)
        .await
        .expect("look the attachment row up")
        .is_some();
    (
        blobs(blob_dir).contains(&slimm_server::media::to_hex(&sha)),
        row,
    )
}

pub fn pack_dir() -> PathBuf {
    let dir = std::env::temp_dir().join(format!("slimm-emoji-pack-{}", Uuid::now_v7()));
    std::fs::create_dir_all(&dir).expect("create temp pack directory");
    dir
}

/// A file the allowlist sniffs as a PNG. Only the magic number is real; the
/// tail is filler, and varying it is how two "different images" are made.
pub fn png(filler: &[u8]) -> Vec<u8> {
    let mut bytes = b"\x89PNG\r\n\x1a\n".to_vec();
    bytes.extend_from_slice(filler);
    bytes
}

pub fn write(dir: &Path, name: &str, bytes: &[u8]) {
    std::fs::write(dir.join(name), bytes).expect("write a fixture file");
}

pub fn outcomes(report: &Report) -> Vec<(String, Outcome)> {
    report
        .files
        .iter()
        .map(|f| (f.file.clone(), f.outcome.clone()))
        .collect()
}
