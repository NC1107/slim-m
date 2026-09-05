// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Every column that points at a user has to have been thought about when an
//! account is deleted.
//!
//! This exists because four of them had not been. `saved_messages` was the
//! one that prompted the audit - its `ON DELETE CASCADE` reads like it covers
//! account deletion and does not, because deleting an account here is a
//! tombstone `UPDATE` setting `deleted_at`, never a row removal, so no
//! cascade ever fires. `poll_votes`, `user_blocks`,
//! `channel_notification_prefs` and `message_forwards.origin_author_id` were
//! all sitting in the same blind spot, and nothing would have said so.
//!
//! Deliberately schema-driven rather than source-reading. It asks the
//! migrated database which columns reference `users`, so a new table joins
//! this list the day it is created and fails until somebody records what
//! should happen to it. A test that grepped `account_deletion.rs` instead
//! could be satisfied by a comment, and would never notice a table nobody
//! had written a line about at all.
//!
//! It does not check that the decision is *carried out* - the behavioural
//! tests do that, one per case, in `account_anonymization.rs` and
//! `saved_messages.rs`. This checks only that a decision exists, which is
//! the part that was actually missing.

use slimm_server::config::Config;
use slimm_server::db;
use sqlx::Row;

mod support;

/// What happens to a user-referencing column when that user's account goes.
#[derive(Debug, Clone, Copy, PartialEq)]
enum OnDelete {
    /// The row is removed: it is the person's own data and nobody else's.
    Purge,
    /// The row stays and the id is nulled: it is content other people can
    /// still see, and removing it would take their conversation with it.
    Anonymize,
    /// The row stays untouched, for a reason that has to be written down.
    Keep(&'static str),
    /// Nothing to do here: a cascade from a table that *is* purged already
    /// takes it, so naming it again would be dead code.
    CascadesFrom(&'static str),
}

/// The decision for every column in the schema that references `users`.
///
/// Adding a table with a user reference and not adding it here fails the
/// test below. That is the whole point: the failure is the prompt to decide,
/// and the entry is the record that somebody did.
const DECISIONS: &[(&str, &str, OnDelete)] = &[
    (
        "access_tokens",
        "user_id",
        OnDelete::CascadesFrom("devices"),
    ),
    ("attachment_uploaders", "uploaded_by", OnDelete::Purge),
    ("canvas_audit_log", "actor_id", OnDelete::Anonymize),
    ("canvas_media_slots", "user_id", OnDelete::Purge),
    ("canvas_objects", "author_id", OnDelete::Anonymize),
    ("canvas_ops", "actor_id", OnDelete::Anonymize),
    ("channel_notification_prefs", "user_id", OnDelete::Purge),
    ("custom_emoji", "uploader_id", OnDelete::Anonymize),
    ("devices", "user_id", OnDelete::Purge),
    (
        "dm_channels",
        "user_a",
        OnDelete::Keep(
            "deleting the row drops the DM channel and cascades its messages, \
             destroying the other participant's own history - the opposite of \
             anonymizing content that stays visible",
        ),
    ),
    (
        "dm_channels",
        "user_b",
        OnDelete::Keep("the other half of the same pair; see user_a"),
    ),
    ("dm_hides", "user_id", OnDelete::Purge),
    ("invite_redemptions", "user_id", OnDelete::Purge),
    ("invites", "created_by", OnDelete::Anonymize),
    ("member_roles", "user_id", OnDelete::Purge),
    ("member_timeouts", "issued_by", OnDelete::Anonymize),
    (
        "member_timeouts",
        "user_id",
        OnDelete::Keep(
            "a timeout lapses by arithmetic at read time and its subject is \
             gone; the row is moderation history about the deployment rather \
             than the person's own data",
        ),
    ),
    ("message_forwards", "origin_author_id", OnDelete::Anonymize),
    ("message_mentions", "user_id", OnDelete::Purge),
    ("message_ops", "actor_id", OnDelete::Anonymize),
    ("messages", "author_id", OnDelete::Anonymize),
    ("moderation_audit_log", "actor_id", OnDelete::Anonymize),
    (
        "moderation_audit_log",
        "subject_id",
        OnDelete::Keep("an audit log of what was done, kept for accountability"),
    ),
    ("password_reset_codes", "issued_by", OnDelete::Anonymize),
    ("password_reset_codes", "user_id", OnDelete::Purge),
    ("pinned_messages", "pinned_by", OnDelete::Anonymize),
    ("poll_votes", "user_id", OnDelete::Purge),
    ("polls", "created_by", OnDelete::Anonymize),
    ("reactions", "user_id", OnDelete::Purge),
    ("read_states", "user_id", OnDelete::Purge),
    ("reports", "reporter_id", OnDelete::Anonymize),
    ("reports", "resolved_by", OnDelete::Anonymize),
    ("saved_messages", "user_id", OnDelete::Purge),
    ("sessions", "user_id", OnDelete::CascadesFrom("devices")),
    ("space_removals", "removed_by", OnDelete::Anonymize),
    (
        "space_removals",
        "user_id",
        OnDelete::Keep("the removal is about them and outlives the account"),
    ),
    ("user_blocks", "blocked_id", OnDelete::Purge),
    ("user_blocks", "blocker_id", OnDelete::Purge),
    ("user_notes", "author_id", OnDelete::Purge),
    (
        "user_notes",
        "subject_id",
        OnDelete::Keep("somebody else's note about them, and theirs to keep"),
    ),
    ("users", "id", OnDelete::Keep("the tombstone itself")),
    ("ws_tickets", "user_id", OnDelete::CascadesFrom("devices")),
];

/// Every `(table, column)` in the migrated schema that points at `users`.
async fn user_references() -> Vec<(String, String)> {
    let (path, _guard) = support::TestDbGuard::new("slimm-deletion-coverage");
    let config = Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..Config::default()
    };
    let pool = db::connect(&config).await.expect("connect + migrate");

    let tables: Vec<String> = sqlx::query(
        "SELECT name FROM sqlite_master WHERE type = 'table' \
         AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_sqlx%' ORDER BY name",
    )
    .fetch_all(&pool)
    .await
    .expect("list tables")
    .into_iter()
    .map(|row| row.get::<String, _>("name"))
    .collect();

    let mut found = Vec::new();
    for table in tables {
        let fks = sqlx::query(&format!("PRAGMA foreign_key_list({table})"))
            .fetch_all(&pool)
            .await
            .expect("foreign keys");
        for fk in fks {
            if fk.get::<String, _>("table") == "users" {
                found.push((table.clone(), fk.get::<String, _>("from")));
            }
        }
    }
    // users.id is what every other reference points at, and has no foreign key of its own to be found.
    found.push(("users".to_owned(), "id".to_owned()));
    found.sort();
    found
}

#[tokio::test]
async fn every_user_reference_has_a_recorded_decision() {
    let found = user_references().await;
    let decided: Vec<(String, String)> = DECISIONS
        .iter()
        .map(|(t, c, _)| ((*t).to_owned(), (*c).to_owned()))
        .collect();

    let undecided: Vec<_> = found.iter().filter(|r| !decided.contains(r)).collect();
    assert!(
        undecided.is_empty(),
        "these columns point at a user and nothing says what happens to them \
         when that account is deleted: {undecided:?}\n\
         Add an entry to DECISIONS saying Purge, Anonymize, Keep or \
         CascadesFrom, and make account_deletion.rs do it. A foreign key is \
         not enough on its own: deleting an account is a tombstone UPDATE, so \
         ON DELETE CASCADE never fires."
    );
}

#[tokio::test]
async fn no_decision_names_a_column_that_no_longer_exists() {
    let found = user_references().await;
    let stale: Vec<_> = DECISIONS
        .iter()
        .filter(|(t, c, _)| !found.contains(&((*t).to_owned(), (*c).to_owned())))
        .map(|(t, c, _)| format!("{t}.{c}"))
        .collect();

    assert!(
        stale.is_empty(),
        "these decisions name columns the schema no longer has, so they are \
         recording a choice about nothing: {stale:?}"
    );
}
