// SPDX-License-Identifier: AGPL-3.0-only
//! `canvas_ops` had no index reaching `created_at` at all until migration
//! 0038, so the op-clock's restart seed and every pass of the sweep paid for
//! a full table scan under the database's one write lock. Left to itself on
//! a database nothing has ever `ANALYZE`d, SQLite can still pick a full scan
//! over an index that exists but is not selective enough to look worth using
//! - the same trap `canvas_index.rs`'s own R-Tree test exists for - so only
//! the plan itself can catch a regression here, the same reasoning that test
//! gives for reading its SQL out of source rather than a copy.

use std::fs;
use std::path::Path;

use sqlx::{Row, SqlitePool};

async fn new_pool(name: &str) -> (SqlitePool, crate::support::TestDbGuard) {
    let (path, guard) = crate::support::TestDbGuard::new(&format!("slimm-{name}"));
    let config = slimm_server::config::Config {
        port: 0,
        database_path: path,
        hash_concurrency: 2,
        ..slimm_server::config::Config::default()
    };
    (
        slimm_server::db::connect(&config).await.expect("connect + migrate"),
        guard,
    )
}

fn read_source(relative: &str) -> String {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(relative);
    fs::read_to_string(&path).unwrap_or_else(|_| panic!("read {relative}"))
}

/// A whole string literal's body, given `anchor` - any unique substring
/// *inside* it, not necessarily its start. Searches backward from `anchor`
/// for the opening quote and forward for the matching close, so the caller
/// only has to name something distinctive about the query, the same way
/// `canvas_index.rs`'s `viewport_sql` locates the query it reads by a marker
/// rather than carrying a copy. `raw` picks `r#"`/`"#` over a plain `"`,
/// since these query bodies carry embedded `"column: Type"` annotations that
/// a bare `"` search would stop at early.
fn extract_containing(source: &str, anchor: &str, raw: bool) -> String {
    let pos = source
        .find(anchor)
        .unwrap_or_else(|| panic!("{anchor:?} no longer appears in the source"));
    let open = if raw { "r#\"" } else { "\"" };
    let start = source[..pos]
        .rfind(open)
        .unwrap_or_else(|| panic!("no opening quote before {anchor:?}"))
        + open.len();
    let close = if raw { "\"#" } else { "\"" };
    let end = source[pos..]
        .find(close)
        .unwrap_or_else(|| panic!("no closing quote after {anchor:?}"))
        + pos;
    source[start..end].to_owned()
}

async fn plan_of(pool: &SqlitePool, sql: &str, binds: &[i64]) -> Vec<String> {
    let explain = format!("EXPLAIN QUERY PLAN {sql}");
    let mut query = sqlx::query(&explain);
    for bind in binds {
        query = query.bind(*bind);
    }
    let rows = query
        .fetch_all(pool)
        .await
        .unwrap_or_else(|err| panic!("plan for {sql:?}: {err}"));
    rows.iter().map(|r| r.get::<String, _>("detail")).collect()
}

fn assert_no_scan(plan: &[String], what: &str) {
    assert!(
        !plan.iter().any(|step| step.contains("SCAN canvas_ops")),
        "{what} fell back to scanning canvas_ops; the plan is {plan:?}"
    );
}

/// `Store::now_ms_unique`'s seed, read straight from `canvas_op_clock.rs`.
/// A bare `MAX(created_at)` cannot use an index that leads with `kind`; this
/// is what proves the `WHERE kind IN (...)` rewrite is still there, not just
/// that the index migration shipped.
#[tokio::test]
async fn the_op_clock_seed_never_scans_canvas_ops() {
    let (pool, _guard) = new_pool("canvas-clock-plan").await;
    let source = read_source("src/store/canvas_op_clock.rs");
    let sql = extract_containing(&source, "WHERE kind IN ('place'", true);
    let plan = plan_of(&pool, &sql, &[]).await;
    assert_no_scan(&plan, "the op-clock seed");
}

/// The sweep's three passes, read straight from `canvas_ops_sweep.rs`. Each
/// is checked with a bind pair that matches zero rows (an empty database),
/// the exact shape that made the unindexed query expensive: nothing to find
/// early means reading every row before answering.
#[tokio::test]
async fn the_sweeps_three_passes_never_scan_canvas_ops() {
    let (pool, _guard) = new_pool("canvas-sweep-plan").await;
    let source = read_source("src/store/canvas_ops_sweep.rs");

    let restores = extract_containing(&source, "kind = 'restore' AND created_at", false);
    let removes = extract_containing(&source, "o.kind = 'remove'", true);
    let clears = extract_containing(&source, "o.kind = 'clear'", true);

    assert_no_scan(&plan_of(&pool, &restores, &[0, 500]).await, "the restore pass");
    assert_no_scan(&plan_of(&pool, &removes, &[0, 500]).await, "the remove pass");
    assert_no_scan(&plan_of(&pool, &clears, &[0, 500]).await, "the clear pass");
}
