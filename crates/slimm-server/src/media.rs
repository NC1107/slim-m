// SPDX-License-Identifier: AGPL-3.0-only
//! Filesystem-backed storage for attachment and avatar bytes, plus the
//! content-type allowlist that decides what may be stored and served at all.
//!
//! Blobs live on disk beside the database rather than as SQLite rows:
//! Litestream replicates only the database file, so multi-megabyte blobs in
//! it would bloat exactly what gets streamed for no backup benefit. See
//! `deploy/README.md` for the backup gap this deliberately leaves.
//!
//! Every write lands via a temp-file-then-rename in the same directory, so a
//! concurrent read of a path being replaced (an avatar overwrite) never
//! observes a partially written file: rename is atomic within one filesystem.
//! File is written before any database row is updated to point at it, so a
//! crash between the two steps leaves an orphaned file (harmless, reclaimed
//! by the sweep or simply wasted bytes) rather than a row that promises bytes
//! which do not exist.
//!
//! `SLIMM_ATTACHMENTS_DIR` and `SLIMM_ATTACHMENT_MAX_BYTES` are ordinary
//! fields on the shared `Config` struct (see `src/config.rs`); this module
//! only turns the resulting path and byte limit into a working [`Media`]
//! handle.

use std::io;
use std::path::PathBuf;
use std::sync::Arc;

use uuid::Uuid;

/// Largest attachment a single upload may store, for [`Media::for_tests`],
/// which builds a handle without a `Config` to read the real default from.
/// Matches `default_attachment_max_bytes` in `src/config.rs`.
const DEFAULT_ATTACHMENT_MAX_BYTES: u64 = 10 * 1024 * 1024;

// --- Content-type allowlist ---

/// One entry in the upload allowlist: the content type stored bytes matching
/// its magic number are served as, and whether that type is safe to render
/// inline in a browser (an image) or must be forced to download.
struct AllowedType {
    content_type: &'static str,
    inline: bool,
    magic: fn(&[u8]) -> bool,
}

const ALLOWED_TYPES: &[AllowedType] = &[
    AllowedType {
        content_type: "image/png",
        inline: true,
        magic: |b| b.starts_with(b"\x89PNG\r\n\x1a\n"),
    },
    AllowedType {
        content_type: "image/jpeg",
        inline: true,
        magic: |b| b.starts_with(b"\xff\xd8\xff"),
    },
    AllowedType {
        content_type: "image/gif",
        inline: true,
        magic: |b| b.starts_with(b"GIF87a") || b.starts_with(b"GIF89a"),
    },
    AllowedType {
        content_type: "image/webp",
        inline: true,
        magic: |b| b.len() >= 12 && &b[0..4] == b"RIFF" && &b[8..12] == b"WEBP",
    },
    AllowedType {
        content_type: "application/pdf",
        inline: false,
        magic: |b| b.starts_with(b"%PDF-"),
    },
];

/// Sniffs `bytes` against the allowlist, returning the content type to store
/// and serve it as. `None` means refuse the upload outright.
///
/// Never derived from a filename extension or a client-declared Content-Type
/// header: both are attacker-controlled input, and trusting either is what
/// would turn this into a stored-XSS vector (a client claiming `image/png`
/// or naming a file `photo.png` cannot talk its way into being served as
/// `text/html` or `image/svg+xml` by any means, because neither is ever
/// checked - only the bytes are, against a fixed allowlist that contains
/// neither).
pub fn sniff_content_type(bytes: &[u8]) -> Option<&'static str> {
    ALLOWED_TYPES
        .iter()
        .find(|t| (t.magic)(bytes))
        .map(|t| t.content_type)
}

/// Whether `content_type` (expected to be one [`sniff_content_type`]
/// returned) is safe to render inline. Everything else is served as a forced
/// download, so a browser is never asked to execute or render content this
/// module cannot vouch for.
pub fn is_inline(content_type: &str) -> bool {
    ALLOWED_TYPES
        .iter()
        .any(|t| t.content_type == content_type && t.inline)
}

/// Longest a sanitized filename may be, in characters.
const FILENAME_MAX_CHARS: usize = 200;

/// Reduces a client-supplied filename to something safe to place inside a
/// quoted `Content-Disposition` header value: printable ASCII plus space
/// only, so a control character (a `\r` or `\n` would otherwise inject a new
/// header line) or non-ASCII text cannot reach the header at all, and no
/// quote, backslash, or path separator, so nothing can break out of the
/// quoted string. The path-separator strip is defence in depth only: storage
/// never uses this value as a path component (files are keyed by content
/// hash or user id), so a `../` sequence in a filename has nowhere to escape
/// to even before sanitizing.
pub fn sanitize_filename(name: &str) -> String {
    let cleaned: String = name
        .chars()
        .map(|c| {
            let safe = (c.is_ascii_graphic() || c == ' ') && !matches!(c, '"' | '\\' | '/');
            if safe { c } else { '_' }
        })
        .take(FILENAME_MAX_CHARS)
        .collect();
    let trimmed = cleaned.trim();
    if trimmed.is_empty() {
        "file".to_owned()
    } else {
        trimmed.to_owned()
    }
}

/// Lowercase hex, matching the idiom already used for the token and identity
/// fingerprint hashes elsewhere in this crate.
pub fn to_hex(bytes: &[u8]) -> String {
    use std::fmt::Write;
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        let _ = write!(out, "{byte:02x}");
    }
    out
}

/// Parses a lowercase (or any-case) hex string back to bytes. `None` for
/// anything that is not a well-formed even-length hex string, which a
/// caller treats as "no such attachment" rather than trying to interpret it
/// as a path or otherwise.
pub fn from_hex(s: &str) -> Option<Vec<u8>> {
    if s.is_empty() || !s.len().is_multiple_of(2) || !s.bytes().all(|b| b.is_ascii_hexdigit()) {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok())
        .collect()
}

// --- Filesystem storage ---

/// A cloneable handle to the on-disk blob store. Cheap to clone (two
/// `PathBuf`s and a `u64`).
#[derive(Debug, Clone)]
pub struct Media {
    attachments_dir: PathBuf,
    avatars_dir: PathBuf,
    max_attachment_bytes: u64,
    /// The deployment-wide ceiling, or `None` for no ceiling. Carried here
    /// rather than on `AppState` because this is where the other size limit
    /// read out of `Config` already lives, and because `AppState` is built by
    /// hand in dozens of test files that have no opinion about it.
    max_total_attachment_bytes: Option<u64>,
    /// Set only by [`Media::for_tests`]; always `None` in a real deployment,
    /// whose media root outlives the process on purpose.
    temp_root: Option<Arc<TempRoot>>,
}

/// Removes the tree it names once the last [`Media`] clone holding it drops.
///
/// Behind an `Arc` because `Media` is cloned into every `AppState` and axum
/// clones that per request; deleting on the first drop would take the
/// directory out from under a live test.
#[derive(Debug)]
struct TempRoot(PathBuf);

impl Drop for TempRoot {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

impl Media {
    /// Creates the storage directories if they do not already exist. Plain
    /// synchronous I/O rather than `spawn_blocking`: this runs once at
    /// process (or test) startup, never on a request path, so a brief block
    /// costs nothing a request would ever notice.
    pub fn new(root: impl Into<PathBuf>, max_attachment_bytes: u64) -> io::Result<Self> {
        let root = root.into();
        let attachments_dir = root.join("attachments");
        let avatars_dir = root.join("avatars");
        std::fs::create_dir_all(&attachments_dir)?;
        std::fs::create_dir_all(&avatars_dir)?;
        Ok(Self {
            attachments_dir,
            avatars_dir,
            max_attachment_bytes,
            max_total_attachment_bytes: None,
            temp_root: None,
        })
    }

    /// A media store rooted in a fresh temp directory. Mirrors
    /// `PushSender::disabled()` and `VoiceService::disabled()`: a harmless
    /// stand-in so every integration test's `AppState` fixture does not have
    /// to think about storage unless it is actually exercising attachments.
    pub fn for_tests() -> Self {
        let root = std::env::temp_dir().join(format!("slimm-media-test-{}", Uuid::now_v7()));
        let mut media = Self::new(root.clone(), DEFAULT_ATTACHMENT_MAX_BYTES)
            .expect("create temp media directories");
        media.temp_root = Some(Arc::new(TempRoot(root)));
        media
    }

    pub fn max_attachment_bytes(&self) -> u64 {
        self.max_attachment_bytes
    }

    /// Sets the deployment-wide ceiling, consuming and returning self so
    /// `main` can build this in one expression.
    pub fn with_total_ceiling(mut self, ceiling: Option<u64>) -> Self {
        self.max_total_attachment_bytes = ceiling;
        self
    }

    pub fn max_total_attachment_bytes(&self) -> Option<u64> {
        self.max_total_attachment_bytes
    }

    fn attachment_path(&self, sha256_hex: &str) -> PathBuf {
        self.attachments_dir.join(sha256_hex)
    }

    fn avatar_path(&self, user_id: &str) -> PathBuf {
        self.avatars_dir.join(user_id)
    }

    pub async fn write_attachment(&self, sha256_hex: &str, bytes: Vec<u8>) -> io::Result<()> {
        write_atomic(self.attachment_path(sha256_hex), bytes).await
    }

    pub async fn read_attachment(&self, sha256_hex: &str) -> io::Result<Vec<u8>> {
        read(self.attachment_path(sha256_hex)).await
    }

    pub async fn delete_attachment(&self, sha256_hex: &str) -> io::Result<()> {
        remove(self.attachment_path(sha256_hex)).await
    }

    pub async fn write_avatar(&self, user_id: &str, bytes: Vec<u8>) -> io::Result<()> {
        write_atomic(self.avatar_path(user_id), bytes).await
    }

    pub async fn read_avatar(&self, user_id: &str) -> io::Result<Vec<u8>> {
        read(self.avatar_path(user_id)).await
    }

    pub async fn delete_avatar(&self, user_id: &str) -> io::Result<()> {
        remove(self.avatar_path(user_id)).await
    }
}

/// Writes `bytes` to `path` via a same-directory temp file plus rename, so a
/// concurrent reader of `path` never observes a partial write. Runs on the
/// blocking pool: this crate's `tokio` features do not include `fs`, and
/// `spawn_blocking` is the same mechanism `tokio::fs` itself is built on.
async fn write_atomic(path: PathBuf, bytes: Vec<u8>) -> io::Result<()> {
    tokio::task::spawn_blocking(move || {
        let dir = path
            .parent()
            .expect("attachment and avatar paths always have a parent directory");
        let tmp_path = dir.join(format!(".tmp-{}", Uuid::now_v7()));
        std::fs::write(&tmp_path, &bytes)?;
        std::fs::rename(&tmp_path, &path)
    })
    .await
    .unwrap_or_else(|e| Err(io::Error::other(e)))
}

async fn read(path: PathBuf) -> io::Result<Vec<u8>> {
    tokio::task::spawn_blocking(move || std::fs::read(path))
        .await
        .unwrap_or_else(|e| Err(io::Error::other(e)))
}

/// Deletes a file, treating "already gone" as success: both the orphan sweep
/// and a message delete's attachment release call this for content that may
/// already have been cleaned up by a previous, interrupted attempt.
async fn remove(path: PathBuf) -> io::Result<()> {
    tokio::task::spawn_blocking(move || match std::fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e),
    })
    .await
    .unwrap_or_else(|e| Err(io::Error::other(e)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sniffs_by_bytes_not_by_claim() {
        assert_eq!(
            sniff_content_type(b"\x89PNG\r\n\x1a\nrest"),
            Some("image/png")
        );
        assert_eq!(sniff_content_type(b"\xff\xd8\xffrest"), Some("image/jpeg"));
        assert_eq!(sniff_content_type(b"GIF89arest"), Some("image/gif"));
        assert_eq!(
            sniff_content_type(b"RIFF\0\0\0\0WEBPrest"),
            Some("image/webp")
        );
        assert_eq!(sniff_content_type(b"%PDF-1.7"), Some("application/pdf"));
        assert_eq!(sniff_content_type(b"<html><script>"), None);
        assert_eq!(sniff_content_type(b"<svg xmlns="), None);
    }

    #[test]
    fn sanitize_strips_header_and_path_injection() {
        assert_eq!(sanitize_filename("photo.png"), "photo.png");
        assert_eq!(sanitize_filename("my photo.png"), "my photo.png");
        assert_eq!(
            sanitize_filename("evil\r\nX-Injected: true.png"),
            "evil__X-Injected: true.png"
        );
        assert_eq!(sanitize_filename("say \"hi\".png"), "say _hi_.png");
        assert_eq!(sanitize_filename("../../etc/passwd"), ".._.._etc_passwd");
        assert_eq!(sanitize_filename(""), "file");
        assert_eq!(sanitize_filename("   "), "file");
    }

    #[test]
    fn hex_roundtrips() {
        let bytes = vec![0u8, 1, 255, 16, 128];
        let hex = to_hex(&bytes);
        assert_eq!(hex, "0001ff1080");
        assert_eq!(from_hex(&hex), Some(bytes));
        assert_eq!(from_hex("not-hex"), None);
        assert_eq!(from_hex("abc"), None, "odd length is rejected");
    }
}

#[cfg(test)]
mod temp_root_tests {
    use super::*;

    #[test]
    fn a_test_media_root_is_removed_when_the_last_clone_drops() {
        let media = Media::for_tests();
        let root = media.attachments_dir.parent().unwrap().to_path_buf();
        assert!(root.exists(), "the root exists while a handle is held");

        let clone = media.clone();
        drop(media);
        assert!(root.exists(), "a surviving clone keeps the root alive");

        drop(clone);
        assert!(!root.exists(), "the last drop removes the root");
    }
}
