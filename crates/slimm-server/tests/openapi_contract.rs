// SPDX-License-Identifier: AGPL-3.0-only
//! Gates schema/openapi.yaml against the routes axum actually serves.
//!
//! Both sides are parsed straight out of their source text rather than
//! trusted by inspection, because a schema that only has to be updated by
//! someone remembering to do it always rots: this project has already
//! shipped with the documented surface stuck at a fraction of the real one.
//!
//! The router side is extracted with a hand-rolled scanner rather than a
//! regex crate, on purpose: `.route(...)` calls span multiple lines and their
//! handler-chain argument (`get(x).post(y)`) has its own parentheses, so a
//! plain regex would either stop at the first inner `)` or need a
//! non-trivial balanced-group workaround. A small brace-counting scanner is
//! both simpler and exact.
//!
//! Extraction is self-checked rather than merely trusted: for every source
//! file, the number of `.route(` call sites the scanner *finds* textually
//! must equal the number it successfully *parses* into a path and at least
//! one method. If a future axum syntax change (or a bug here) makes parsing
//! silently give up on a call, that mismatch fails loudly by itself, rather
//! than the gate quietly comparing an incomplete route list against the
//! schema forever.

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

// --- HTTP methods ---

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Method {
    Get,
    Post,
    Put,
    Patch,
    Delete,
    Head,
    Options,
    Trace,
}

impl Method {
    fn parse(word: &str) -> Option<Method> {
        Some(match word {
            "get" => Method::Get,
            "post" => Method::Post,
            "put" => Method::Put,
            "patch" => Method::Patch,
            "delete" => Method::Delete,
            "head" => Method::Head,
            "options" => Method::Options,
            "trace" => Method::Trace,
            _ => return None,
        })
    }

    fn as_str(self) -> &'static str {
        match self {
            Method::Get => "GET",
            Method::Post => "POST",
            Method::Put => "PUT",
            Method::Patch => "PATCH",
            Method::Delete => "DELETE",
            Method::Head => "HEAD",
            Method::Options => "OPTIONS",
            Method::Trace => "TRACE",
        }
    }
}

const HTTP_VERBS: [&str; 8] = [
    "get", "post", "put", "patch", "delete", "head", "options", "trace",
];

/// A segment of an alphanumeric-plus-underscore identifier; used to make sure
/// a matched verb word is a whole token (`delete`) and not part of a longer
/// one (`delete_account`) or a preceding qualifier (`axum::routing::delete`
/// must still match, since `:` is not an identifier character).
fn is_ident_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

// --- Router-side extraction ---

#[derive(Debug, Clone)]
struct RouterRoute {
    method: Method,
    path: String,
    file: String,
    line: usize,
}

/// Every `.route(` module under `src/http`, one file per HTTP surface area
/// plus the top-level `src/http.rs` (healthz, version). At least this many
/// files must contribute a route, or route discovery itself is broken (a
/// module went missing from disk, or the directory walk silently found
/// nothing).
const MIN_ROUTE_FILES: usize = 10;

fn matching_close_paren(bytes: &[u8], open: usize) -> Option<usize> {
    debug_assert_eq!(bytes[open], b'(');
    let mut depth = 0i32;
    for (i, &b) in bytes.iter().enumerate().skip(open) {
        match b {
            b'(' => depth += 1,
            b')' => {
                depth -= 1;
                if depth == 0 {
                    return Some(i);
                }
            }
            _ => {}
        }
    }
    None
}

/// Pulls the HTTP verb tokens (`get`, `post`, ...) out of a route's handler
/// argument, e.g. `get(list).post(create)` or `axum::routing::delete(revoke)`.
/// Deliberately only scans the handler-chain text, not the path string, so a
/// path segment that happens to contain a verb word (`/get-started`) can
/// never be mistaken for a method.
fn extract_methods(chain: &str) -> Vec<Method> {
    let bytes = chain.as_bytes();
    let mut methods = Vec::new();
    for word in HTTP_VERBS {
        let mut from = 0usize;
        while let Some(rel) = chain[from..].find(word) {
            let start = from + rel;
            let end = start + word.len();
            let before_is_ident = start > 0 && is_ident_char(bytes[start - 1]);
            let after_is_ident = end < bytes.len() && is_ident_char(bytes[end]);
            if !before_is_ident && !after_is_ident {
                let mut j = end;
                while j < bytes.len() && bytes[j].is_ascii_whitespace() {
                    j += 1;
                }
                if j < bytes.len() && bytes[j] == b'(' {
                    methods.push(Method::parse(word).expect("word is a known HTTP_VERBS entry"));
                }
            }
            from = end;
        }
    }
    methods.sort();
    methods.dedup();
    methods
}

/// Parses one `.route(` call's argument text (everything between its
/// parentheses) into the path literal and the methods bound to it. Returns
/// `None` if the shape is not the expected `"path", handler-chain`, which the
/// caller treats as an extractor failure, not as "this route has no methods".
fn parse_route_call(arg_text: &str) -> Option<(String, Vec<Method>)> {
    let after_open_quote = &arg_text[arg_text.find('"')? + 1..];
    let close_quote = after_open_quote.find('"')?;
    let path = after_open_quote[..close_quote].to_string();
    let methods = extract_methods(&after_open_quote[close_quote + 1..]);
    if path.is_empty() || methods.is_empty() {
        return None;
    }
    Some((path, methods))
}

fn line_of(text: &str, byte_idx: usize) -> usize {
    text[..byte_idx].matches('\n').count() + 1
}

fn http_source_files(manifest_dir: &Path) -> Vec<PathBuf> {
    let mut files = vec![manifest_dir.join("src/http.rs")];
    let http_dir = manifest_dir.join("src/http");
    let mut submodules: Vec<PathBuf> = fs::read_dir(&http_dir)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", http_dir.display()))
        .map(|entry| entry.expect("readable dir entry").path())
        .filter(|p| p.extension().is_some_and(|ext| ext == "rs"))
        .collect();
    submodules.sort();
    files.extend(submodules);
    files
}

/// Extracts every `(method, path)` the axum router actually serves, from the
/// source text of `src/http.rs` and `src/http/*.rs`.
///
/// Panics (rather than returning a partial result) if the self-check
/// described at the top of this file fails, since a gate that can silently
/// under-count routes is worse than no gate.
fn extract_router_routes() -> Vec<RouterRoute> {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut routes = Vec::new();
    let mut files_with_routes = 0usize;

    for file in http_source_files(manifest_dir) {
        let text = fs::read_to_string(&file)
            .unwrap_or_else(|e| panic!("cannot read {}: {e}", file.display()));
        let raw_call_sites = text.matches(".route(").count();
        if raw_call_sites == 0 {
            continue;
        }
        files_with_routes += 1;

        let bytes = text.as_bytes();
        let mut parsed_call_sites = 0usize;
        for (idx, _) in text.match_indices(".route(") {
            let open_paren = idx + ".route".len();
            let close_paren = matching_close_paren(bytes, open_paren).unwrap_or_else(|| {
                panic!(
                    "{}:{}: unbalanced parentheses reading a `.route(` call; \
                     the extractor in tests/openapi_contract.rs cannot find where it ends",
                    file.display(),
                    line_of(&text, idx)
                )
            });
            let arg_text = &text[open_paren + 1..close_paren];
            let Some((path, methods)) = parse_route_call(arg_text) else {
                continue;
            };
            parsed_call_sites += 1;
            let line = line_of(&text, idx);
            let rel_file = file
                .strip_prefix(manifest_dir)
                .unwrap_or(&file)
                .to_string_lossy()
                .into_owned();
            for method in methods {
                routes.push(RouterRoute {
                    method,
                    path: path.clone(),
                    file: rel_file.clone(),
                    line,
                });
            }
        }

        // Self-check: the found-versus-parsed count must match, or the scanner
        // regressed on this file's syntax (see this file's module doc).
        assert_eq!(
            parsed_call_sites,
            raw_call_sites,
            "route extractor regression in {}: found {raw_call_sites} literal `.route(` call(s) \
             but only parsed {parsed_call_sites} of them into a path and methods; fix \
             parse_route_call/extract_methods in tests/openapi_contract.rs before trusting this gate",
            file.display()
        );
    }

    assert!(
        !routes.is_empty(),
        "route extractor found zero routes anywhere under src/http; it is almost \
         certainly broken, not the codebase having no routes"
    );
    assert!(
        files_with_routes >= MIN_ROUTE_FILES,
        "route extractor only found `.route(` syntax in {files_with_routes} file(s) under \
         src/http, expected at least {MIN_ROUTE_FILES} (one per route module: http.rs plus \
         auth, channels, invites, messages, push, reactions, safety, sync, ws); either a route \
         module went missing or file discovery in tests/openapi_contract.rs is broken"
    );

    routes
}

// --- Schema-side extraction ---

#[derive(Debug, Clone)]
struct SchemaRoute {
    method: Method,
    path: String,
    line: usize,
}

/// Extracts every `(method, path)` documented under `paths:` in
/// schema/openapi.yaml.
///
/// This is a line-based reader tuned to this file's consistent 2-space
/// indent, not a general YAML parser: a path key sits at exactly two spaces
/// of indent (`  /channels:`), and an HTTP-method key for it sits at exactly
/// four (`    get:`), sibling to things like `parameters:` that are ignored
/// because they are not one of the known verbs.
fn extract_schema_routes(repo_root: &Path) -> Vec<SchemaRoute> {
    let schema_path = repo_root.join("schema/openapi.yaml");
    let text = fs::read_to_string(&schema_path)
        .unwrap_or_else(|e| panic!("cannot read {}: {e}", schema_path.display()));

    let mut routes = Vec::new();
    let mut in_paths = false;
    let mut current_path: Option<String> = None;

    for (i, raw_line) in text.lines().enumerate() {
        let line_no = i + 1;
        if raw_line == "paths:" {
            in_paths = true;
            continue;
        }
        if !in_paths {
            continue;
        }
        if raw_line.trim().is_empty() {
            continue;
        }
        // A line back at column 0 (`components:`) ends the `paths:` block.
        if !raw_line.starts_with(' ') {
            break;
        }

        let indent = raw_line.len() - raw_line.trim_start().len();
        let trimmed = raw_line.trim();

        if indent == 2 && trimmed.starts_with('/') && trimmed.ends_with(':') {
            current_path = Some(trimmed[..trimmed.len() - 1].to_string());
            continue;
        }

        if indent == 4
            && let Some(key) = trimmed.strip_suffix(':')
            && !key.is_empty()
            && !key.contains(' ')
            && let Some(method) = Method::parse(key)
        {
            let path = current_path.clone().unwrap_or_else(|| {
                panic!(
                    "{}:{line_no}: found method `{key}:` with no enclosing path key above it",
                    schema_path.display()
                )
            });
            routes.push(SchemaRoute {
                method,
                path,
                line: line_no,
            });
        }
    }

    assert!(
        !routes.is_empty(),
        "schema route extractor found zero operations under `paths:` in {}; it is almost \
         certainly broken, not the schema having no paths",
        schema_path.display()
    );

    routes
}

// --- Comparison ---

/// Normalizes a path template so axum's `{channel_id}` and the schema's
/// `{channelId}` compare equal: both spell "one path parameter here", just
/// with a different naming convention for it. Every other segment (the
/// static parts of the path, and the number and order of segments) is
/// compared literally, so a genuinely different path still fails.
fn normalize(path: &str) -> String {
    path.split('/')
        .map(|segment| {
            if segment.starts_with('{') && segment.ends_with('}') && segment.len() >= 2 {
                "{}"
            } else {
                segment
            }
        })
        .collect::<Vec<_>>()
        .join("/")
}

#[test]
fn openapi_matches_router() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let repo_root = manifest_dir
        .parent()
        .and_then(Path::parent)
        .expect("crates/slimm-server is two directories below the repo root");

    let router_routes = extract_router_routes();
    let schema_routes = extract_schema_routes(repo_root);

    let router_keys: BTreeSet<(Method, String)> = router_routes
        .iter()
        .map(|r| (r.method, normalize(&r.path)))
        .collect();
    let schema_keys: BTreeSet<(Method, String)> = schema_routes
        .iter()
        .map(|r| (r.method, normalize(&r.path)))
        .collect();

    let mut problems = Vec::new();

    for route in &router_routes {
        let key = (route.method, normalize(&route.path));
        if !schema_keys.contains(&key) {
            problems.push(format!(
                "{} {} is served by the router ({}:{}) but is not documented in schema/openapi.yaml",
                route.method.as_str(),
                route.path,
                route.file,
                route.line
            ));
        }
    }

    for route in &schema_routes {
        let key = (route.method, normalize(&route.path));
        if !router_keys.contains(&key) {
            problems.push(format!(
                "{} {} is documented in schema/openapi.yaml:{} but is not served by any router route",
                route.method.as_str(),
                route.path,
                route.line
            ));
        }
    }

    problems.sort();
    problems.dedup();

    assert!(
        problems.is_empty(),
        "\nschema/openapi.yaml has drifted from the routes the server actually serves:\n\n{}\n",
        problems.join("\n")
    );
}
