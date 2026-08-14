// SPDX-License-Identifier: AGPL-3.0-only
//! Shared by every integration test binary via `mod support;` (a `mod.rs`
//! directory is never auto-discovered as its own test target, unlike a
//! sibling `main.rs`). A subdirectory binary reaches it with
//! `#[path = "../support/mod.rs"] mod support;`.

use std::path::{Path, PathBuf};

use slimm_server::ids::{ChannelId, UserId};
use slimm_server::presence::PresenceTracker;
use slimm_server::store::Store;

/// [`slimm_server::push::message_recipients`] against a fresh, empty
/// [`PresenceTracker`] - shared by every push-recipient test that has no
/// opinion about `@here`, so a perpetually-disconnected tracker is a correct
/// no-op stand-in rather than a parameter each call site has to carry.
///
/// Allowed dead: this module is included by every test binary, and most of
/// them never touch push recipients at all.
#[allow(dead_code)]
pub async fn wake_recipients(
    store: &Store,
    channel_id: ChannelId,
    author_id: UserId,
    content: &str,
) -> anyhow::Result<Vec<UserId>> {
    slimm_server::push::message_recipients(
        store,
        channel_id,
        author_id,
        content,
        &PresenceTracker::new(),
    )
    .await
}

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

/// Blanks `//` and `/* */` comments and `"..."`/raw-string (`r"..."`,
/// `r#"..."#`, ...) literals to spaces, keeping every byte's position, so
/// [function_body]'s brace count only ever sees real code.
///
/// A stray unmatched `}` inside an ordinary `//` comment - "think of this
/// like a code block }" is enough - closed a naive brace-depth scan the
/// moment it appeared, hiding a real second `.fetch_all(`/`&self.pool`
/// call placed after it in the actual function; reproduced directly,
/// independently, against both `canvas_index.rs`'s and
/// `thread_reply_count.rs`'s own former private copies of this logic
/// before this shared one replaced them. Raw strings need their own
/// handling because this crate's own SQL literals (`r#"SELECT ..."#`) are
/// exactly that shape.
#[allow(dead_code)]
pub fn code_only(source: &str) -> String {
    let bytes = source.as_bytes();
    let mut out = vec![b' '; bytes.len()];
    let mut i = 0usize;
    while i < bytes.len() {
        if bytes[i] == b'r' {
            let mut hashes = 0usize;
            let mut j = i + 1;
            while j < bytes.len() && bytes[j] == b'#' {
                hashes += 1;
                j += 1;
            }
            if j < bytes.len() && bytes[j] == b'"' {
                let close: Vec<u8> = std::iter::once(b'"')
                    .chain(std::iter::repeat_n(b'#', hashes))
                    .collect();
                let mut k = j + 1;
                while k < bytes.len() && bytes[k..].get(..close.len()) != Some(close.as_slice()) {
                    k += 1;
                }
                let end = (k + close.len()).min(bytes.len());
                for idx in i..end {
                    if bytes[idx] == b'\n' {
                        out[idx] = b'\n';
                    }
                }
                i = end.max(i + 1);
                continue;
            }
        }
        if bytes[i] == b'"' {
            let mut k = i + 1;
            while k < bytes.len() && bytes[k] != b'"' {
                k += if bytes[k] == b'\\' { 2 } else { 1 };
            }
            let end = (k + 1).min(bytes.len());
            for idx in i..end {
                if bytes[idx] == b'\n' {
                    out[idx] = b'\n';
                }
            }
            i = end;
            continue;
        }
        if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'/') {
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'*') {
            let mut k = i + 2;
            while k < bytes.len() && bytes.get(k..k + 2) != Some(b"*/") {
                k += 1;
            }
            let end = (k + 2).min(bytes.len());
            for idx in i..end {
                if bytes[idx] == b'\n' {
                    out[idx] = b'\n';
                }
            }
            i = end;
            continue;
        }
        out[i] = bytes[i];
        i += 1;
    }
    String::from_utf8(out)
        .expect("only ever ASCII space/newline or original bytes, so always valid utf-8")
}

/// A function's body, from its signature's `marker` to the matching closing
/// brace, by depth counting over [code_only] rather than the raw source, so
/// a comment's or a string's own brace-shaped text cannot end the scan
/// early. Panics naming `marker` (function no longer found) or `source`
/// (unterminated) rather than returning a `Result`, since every caller is a
/// test whose only recovery from either is to fail loudly anyway.
#[allow(dead_code)]
pub fn function_body(source: &str, marker: &str) -> String {
    let scrubbed = code_only(source);
    let start = scrubbed
        .find(marker)
        .unwrap_or_else(|| panic!("{marker} no longer appears in the source"));
    let mut depth = 0i32;
    let mut opened = false;
    for (i, ch) in scrubbed[start..].char_indices() {
        match ch {
            '{' => {
                depth += 1;
                opened = true;
            }
            '}' => {
                depth -= 1;
                if opened && depth == 0 {
                    return scrubbed[start..start + i + 1].to_owned();
                }
            }
            _ => {}
        }
    }
    panic!("{marker}'s body has no matching closing brace")
}

#[allow(dead_code)]
/// The SQL of the first `sqlx::query*!` call whose literal contains [anchor],
/// plain or raw.
///
/// Anchored to a real macro call rather than to the nearest quote, because the
/// nearest quote can belong to a comment. A comment quoting an older version of
/// the query is extracted and validated in place of the code by a bare search,
/// so the query itself can regress to a scan while this passes - the
/// source-reading-gate trap `support::code_only` exists for, demonstrated
/// against this very file before it was written this way. Asserting the anchor
/// is unique does not close it: once the real query stops matching, the stale
/// comment is the only occurrence left.
///
/// `code_only` blanks comments and strings in place and keeps every byte
/// offset, so a call site found in its output is a call site in real code, and
/// the literal is then read back out of the original source at that offset.
pub fn query_literal_containing(source: &str, anchor: &str) -> String {
    let code = code_only(source);
    let mut from = 0usize;
    while let Some(rel) = code[from..].find("query") {
        let at = from + rel;
        from = at + 1;
        let Some(paren) = code[at..].find('(') else {
            continue;
        };
        let name = &code[at..at + paren];
        let macro_call = name.ends_with('!')
            && name[..name.len() - 1]
                .chars()
                .all(|c| c.is_alphanumeric() || c == '_');
        if !macro_call {
            continue;
        }
        if let Some(sql) = literal_at(source, at + paren + 1)
            && sql.contains(anchor)
        {
            return sql;
        }
    }
    panic!("no sqlx query literal contains {anchor:?}; has the query itself changed?")
}

/// The string literal starting at the next non-whitespace byte, `r#"..."#`
/// included, or `None` when what follows is not one.
fn literal_at(source: &str, from: usize) -> Option<String> {
    let bytes = source.as_bytes();
    let mut i = from;
    while i < bytes.len() && bytes[i].is_ascii_whitespace() {
        i += 1;
    }
    if bytes.get(i) == Some(&b'r') {
        let mut hashes = 0usize;
        let mut j = i + 1;
        while bytes.get(j) == Some(&b'#') {
            hashes += 1;
            j += 1;
        }
        if bytes.get(j) != Some(&b'"') {
            return None;
        }
        let close: String = std::iter::once('"')
            .chain(std::iter::repeat_n('#', hashes))
            .collect();
        let start = j + 1;
        let end = source[start..].find(&close)? + start;
        return Some(source[start..end].to_owned());
    }
    if bytes.get(i) == Some(&b'"') {
        let start = i + 1;
        let end = source[start..].find('"')? + start;
        return Some(source[start..end].to_owned());
    }
    None
}
