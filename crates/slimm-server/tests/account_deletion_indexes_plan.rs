// SPDX-License-Identifier: AGPL-3.0-only
//! The four predicates migration 0047 covers, each read out of the source it
//! really runs from, the `canvas_ops/index_plan.rs` technique. Asserting the
//! migration shipped would only prove the index exists; reading the query
//! back means an edit that stops using the index fails here rather than
//! quietly returning to a full scan.

mod support;

use std::fs;
use std::path::Path;

use sqlx::{Row, SqlitePool};

async fn new_pool(name: &str) -> (SqlitePool, support::TestDbGuard) {
    let (path, guard) = support::TestDbGuard::new(name);
    let config = slimm_server::config::Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..slimm_server::config::Config::default()
    };
    (
        slimm_server::db::connect(&config)
            .await
            .expect("connect + migrate"),
        guard,
    )
}

fn source_of(relative: &str) -> String {
    fs::read_to_string(Path::new(env!("CARGO_MANIFEST_DIR")).join(relative))
        .unwrap_or_else(|_| panic!("read {relative}"))
}

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
fn query_literal_containing(source: &str, anchor: &str) -> String {
    let code = support::code_only(source);
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

/// A 16-byte blob per placeholder, matching the affinity of the id columns
/// every query here binds; `0i64` plans the same but claims the wrong type.
async fn plan_of(pool: &SqlitePool, sql: &str, binds: usize) -> Vec<String> {
    let explain = format!("EXPLAIN QUERY PLAN {sql}");
    let mut query = sqlx::query(&explain);
    for _ in 0..binds {
        query = query.bind(vec![0u8; 16]);
    }
    query
        .fetch_all(pool)
        .await
        .expect("plan")
        .iter()
        .map(|row| row.get::<String, _>("detail"))
        .collect()
}

/// The `canvas_ops/index_plan.rs` check rather than a bare `SCAN` prefix:
/// every table here is WITHOUT ROWID, where a full scan can also plan as
/// `SEARCH ... USING PRIMARY KEY` with no constraint in parentheses.
fn assert_no_scan(plan: &[String], what: &str) {
    let scan = plan.iter().find(|step| {
        step.starts_with("SCAN") || (step.contains("USING PRIMARY KEY") && !step.contains('('))
    });
    assert!(
        scan.is_none(),
        "{what} fell back to a full scan; the plan is {plan:?}"
    );
}

fn assert_uses(plan: &[String], index: &str, what: &str) {
    assert!(
        plan.iter().any(|step| step.contains(index)),
        "{what} must seek {index}; the plan is {plan:?}"
    );
}

#[tokio::test]
async fn deleting_an_account_seeks_the_reactions_index() {
    let (pool, _guard) = new_pool("slimm-deletion-plan-reactions").await;
    let source = source_of("src/store/account_deletion.rs");
    let sql = query_literal_containing(&source, "DELETE FROM reactions WHERE user_id");

    let plan = plan_of(&pool, &sql, 1).await;
    assert_uses(&plan, "reactions_user", "the reaction cleanup");
    assert_no_scan(&plan, "the reaction cleanup");
}

#[tokio::test]
async fn deleting_an_account_seeks_the_uploader_index() {
    let (pool, _guard) = new_pool("slimm-deletion-plan-uploaders").await;
    let source = source_of("src/store/account_deletion.rs");
    let sql = query_literal_containing(
        &source,
        "DELETE FROM attachment_uploaders WHERE uploaded_by",
    );

    let plan = plan_of(&pool, &sql, 1).await;
    assert_uses(
        &plan,
        "attachment_uploaders_uploaded_by",
        "the uploader cleanup",
    );
    assert_no_scan(&plan, "the uploader cleanup");
}

#[tokio::test]
async fn deleting_an_account_seeks_the_overwrite_index() {
    let (pool, _guard) = new_pool("slimm-deletion-plan-overwrites").await;
    let source = source_of("src/store/account_deletion.rs");
    let sql = query_literal_containing(&source, "DELETE FROM channel_overwrites WHERE target_type");

    let plan = plan_of(&pool, &sql, 1).await;
    assert_uses(
        &plan,
        "channel_overwrites_target",
        "the member overwrite cleanup",
    );
    assert_no_scan(&plan, "the member overwrite cleanup");
}

/// The same index, reached by the other caller. Deleting a role clears its
/// overwrites through the identical shape, so narrowing the index to
/// `(target_id)` would have to fail here as well as above.
#[tokio::test]
async fn deleting_a_role_seeks_the_overwrite_index() {
    let (pool, _guard) = new_pool("slimm-deletion-plan-role-overwrites").await;
    let source = source_of("src/store/roles.rs");
    let sql = query_literal_containing(&source, "DELETE FROM channel_overwrites WHERE target_type");

    let plan = plan_of(&pool, &sql, 1).await;
    assert_uses(
        &plan,
        "channel_overwrites_target",
        "the role overwrite cleanup",
    );
    assert_no_scan(&plan, "the role overwrite cleanup");
}

/// Not part of account deletion: `previously_visible_to` runs this on every
/// role-scoped overwrite edit, and the (user_id, role_id) primary key cannot
/// serve a bare `role_id` predicate.
#[tokio::test]
async fn listing_a_roles_members_seeks_the_member_roles_index() {
    let (pool, _guard) = new_pool("slimm-deletion-plan-member-roles").await;
    let source = source_of("src/store/roles.rs");
    let sql = query_literal_containing(&source, "FROM member_roles WHERE role_id");

    let plan = plan_of(&pool, &sql, 1).await;
    assert_uses(&plan, "member_roles_role", "the role member list");
    assert_no_scan(&plan, "the role member list");
}

/// The extraction's own guard, from a review that demonstrated the failure
/// against this file's first version: a comment quoting an older copy of the
/// query satisfied a bare search, so the real query could regress to a scan
/// with every test here still green.
#[test]
fn a_stale_comment_quoting_the_old_query_does_not_satisfy_the_gate() {
    let regressed = r#"
        // Formerly: "DELETE FROM reactions WHERE user_id = ?"
        sqlx::query!("DELETE FROM reactions WHERE hex(user_id) = hex(?)", user_id)
    "#;
    let found = std::panic::catch_unwind(|| {
        query_literal_containing(regressed, "DELETE FROM reactions WHERE user_id")
    });
    assert!(
        found.is_err(),
        "a comment is not code; the gate must refuse rather than validate the comment's SQL"
    );
}

/// The other half: a decoy comment must not shadow a query that is still real.
#[test]
fn the_live_query_is_read_past_a_comment_quoting_it() {
    let source = r#"
        // See "DELETE FROM reactions WHERE user_id = ?" below.
        sqlx::query!("DELETE FROM reactions WHERE user_id = ? AND emoji = ?", a, b)
    "#;
    assert_eq!(
        query_literal_containing(source, "DELETE FROM reactions WHERE user_id"),
        "DELETE FROM reactions WHERE user_id = ? AND emoji = ?"
    );
}
