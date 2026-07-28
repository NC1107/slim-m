// SPDX-License-Identifier: AGPL-3.0-only
//! Shared by every integration test binary via `mod support;` (a `mod.rs`
//! directory is never auto-discovered as its own test target, unlike a
//! sibling `main.rs`). A subdirectory binary reaches it with
//! `#[path = "../support/mod.rs"] mod support;`.

use std::path::{Path, PathBuf};

/// Deletes its temp SQLite database, and its `-wal`/`-shm` siblings, on drop.
///
/// Runs on a panicking test too: `Drop` still runs during unwind, which is
/// exactly the case that matters, since a failing test is the one that gets
/// re-run and accumulates.
pub struct TestDbGuard(PathBuf);

impl TestDbGuard {
    /// A fresh unique path under `prefix` in the system temp dir, paired with
    /// a guard that removes it (and its `-wal`/`-shm` siblings) on drop.
    pub fn new(prefix: &str) -> (String, Self) {
        let path = std::env::temp_dir().join(format!("{prefix}-{}.db", uuid::Uuid::now_v7()));
        let display = path.to_string_lossy().into_owned();
        (display, Self(path))
    }
}

impl Drop for TestDbGuard {
    fn drop(&mut self) {
        remove(&self.0);
        remove(&sibling(&self.0, "-wal"));
        remove(&sibling(&self.0, "-shm"));
    }
}

fn sibling(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.as_os_str().to_owned();
    name.push(suffix);
    PathBuf::from(name)
}

fn remove(path: &Path) {
    let _ = std::fs::remove_file(path);
}

/// Deletes a temp *directory tree* on drop, for the fixtures that build a
/// media root or an import pack rather than a database.
///
/// Allowed dead: this module is included by every test binary, and most of
/// them have no directory fixture to guard.
#[allow(dead_code)]
pub struct TestDirGuard(PathBuf);

#[allow(dead_code)]
impl TestDirGuard {
    pub fn new(prefix: &str) -> (PathBuf, Self) {
        let path = std::env::temp_dir().join(format!("{prefix}-{}", uuid::Uuid::now_v7()));
        (path.clone(), Self(path))
    }
}

impl Drop for TestDirGuard {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
