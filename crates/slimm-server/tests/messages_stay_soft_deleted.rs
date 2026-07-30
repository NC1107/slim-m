// SPDX-License-Identifier: AGPL-3.0-only
//! `messages` rows are never hard-deleted, because `messages_fts` is keyed on
//! a rowid SQLite is free to renumber.
//!
//! `0002_core_schema.sql` declares the index `content='messages',
//! content_rowid='rowid'`, and `messages` is `PRIMARY KEY (channel_id, seq)`
//! with no `INTEGER PRIMARY KEY` alias. SQLite documents VACUUM as free to
//! renumber the rowids of any table lacking that alias, and the FTS shadow
//! tables are carried across unchanged - so a VACUUM could leave every index
//! entry pointing at a different message. Search would then return rows that
//! do not contain the query and miss the ones that do, silently, and the
//! first place it lands is the `VACUUM INTO` hot copy the Phase 9 backup
//! story is built on. `0015_canvas_rtree.sql` refused exactly this licence
//! for the R-Tree and gave `canvas_objects` an explicit `rt_id INTEGER
//! PRIMARY KEY`; FTS never got the same treatment.
//!
//! What makes that inert today is not the schema, it is a *behaviour*:
//! deletion is `UPDATE messages SET deleted_at = ?`, so rows are only ever
//! added. Rowids stay gapless, and VACUUM rewriting 1..N as 1..N reassigns
//! the identical numbers. The index survives because nothing has ever left a
//! hole for the compaction to close.
//!
//! That is an assumption holding up a correctness property, and nothing was
//! checking it. A retention policy, an account purge, or a compaction pass
//! that hard-deletes even one row puts a gap in the sequence and re-arms the
//! whole thing, with no test failing and no symptom until somebody restores a
//! backup and searches it.
//!
//! So this test pins the assumption rather than the schema. The real fix is
//! to give `messages` an explicit rowid alias and rebuild the index against
//! it, which is a table rebuild over live message data and wants a person
//! watching the deploy; see CLAUDE.md's owner list. Until then, whoever adds
//! the first hard delete finds out here that they have to do that rebuild
//! first, at the moment it starts to matter rather than after a silent
//! corruption.

use std::fs;
use std::path::{Path, PathBuf};

fn crate_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

/// Every `.rs` under `src/` and every `.sql` under `migrations/`.
fn sources() -> Vec<PathBuf> {
    let mut found = Vec::new();
    for (dir, ext) in [("src", "rs"), ("migrations", "sql")] {
        collect(&crate_root().join(dir), ext, &mut found);
    }
    found
}

fn collect(dir: &Path, ext: &str, out: &mut Vec<PathBuf>) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect(&path, ext, out);
        } else if path.extension().is_some_and(|e| e == ext) {
            out.push(path);
        }
    }
}

/// Finds `DELETE FROM messages` naming that table exactly.
///
/// The trailing character matters: `message_attachments` and `messages_fts`
/// are different tables and both are legitimately deleted from, the latter by
/// the external-content triggers that keep the index in step.
fn hard_deletes_messages(text: &str) -> bool {
    let normalized = text.to_ascii_lowercase().replace(['\n', '\r'], " ");
    let mut haystack = normalized.as_str();
    while let Some(at) = haystack.find("delete from messages") {
        let rest = &haystack[at + "delete from messages".len()..];
        let next = rest.chars().next();
        if !next.is_some_and(|c| c.is_ascii_alphanumeric() || c == '_') {
            return true;
        }
        haystack = rest;
    }
    false
}

#[test]
fn nothing_hard_deletes_a_message_row() {
    let offenders: Vec<String> = sources()
        .into_iter()
        .filter(|p| hard_deletes_messages(&fs::read_to_string(p).unwrap_or_default()))
        .map(|p| p.display().to_string())
        .collect();

    assert!(
        offenders.is_empty(),
        "these hard-delete from `messages`: {offenders:?}\n\
         Deletion here has always been `UPDATE messages SET deleted_at = ?`, \
         and that is what keeps the table's rowids gapless. `messages_fts` is \
         keyed on those rowids and `messages` has no INTEGER PRIMARY KEY, so \
         a gap lets VACUUM renumber the table out from under the index and \
         search starts answering with the wrong rows, silently, inside the \
         VACUUM INTO backup copy first.\n\
         If this delete is genuinely wanted, `messages` needs an explicit \
         rowid alias and the FTS index rebuilt against it in the same change. \
         See this file's own doc comment.",
    );
}

/// The check has to be able to say yes, or it passes for every future file
/// by being unable to recognise the thing it forbids.
#[test]
fn the_check_recognises_a_hard_delete_when_there_is_one() {
    assert!(hard_deletes_messages("DELETE FROM messages WHERE id = ?"));
    assert!(hard_deletes_messages("delete from messages;"));
    assert!(hard_deletes_messages(
        "DELETE FROM messages\n             WHERE deleted_at IS NOT NULL"
    ));
}

/// And it must not fire on the two neighbours that are deleted from all the
/// time, or somebody will delete the assertion rather than the delete.
#[test]
fn the_check_leaves_the_neighbouring_tables_alone() {
    assert!(!hard_deletes_messages(
        "DELETE FROM message_attachments WHERE message_id = ?"
    ));
    assert!(!hard_deletes_messages("DELETE FROM messages_fts"));
    assert!(!hard_deletes_messages(
        "UPDATE messages SET deleted_at = ? WHERE id = ?"
    ));
}

/// Guards the scan itself: a walker that found nothing would make the real
/// assertion pass vacuously, which is the failure mode this whole file
/// exists to avoid one level down.
#[test]
fn the_scan_reaches_real_files() {
    let files = sources();
    assert!(
        files.len() > 40,
        "only {} source files scanned; the walker is not reaching them",
        files.len()
    );
    assert!(
        files.iter().any(|p| p.ends_with("store/messages.rs")),
        "store/messages.rs is where the soft delete lives and was not scanned",
    );
    assert!(
        files.iter().any(|p| p.ends_with("0002_core_schema.sql")),
        "the schema that declares messages_fts was not scanned",
    );
}
