// SPDX-License-Identifier: AGPL-3.0-only
//! Gates the bodies the server really sends against the bodies
//! schema/openapi.yaml promises.
//!
//! `tests/openapi_contract.rs` already pins the route surface, but only the
//! method and path of it. Everything inside a response - which fields exist,
//! their types, their nullability, the status code and content type they
//! arrive under - was checked by review alone, on three sides that are all
//! written by hand: the Rust DTO, this schema, and the Dart model in
//! `client/packages/api`. This test removes the schema-to-server half of that
//! gap by driving every documented operation for real and validating the
//! answer against the document.
//!
//! Both directions of drift fail, and deliberately so:
//!
//! - The schema promising a field the server does not send is caught by
//!   `required` in the validator. A client written from the schema would have
//!   read that field.
//! - The server sending a field the schema does not document is caught by the
//!   second pass in `openapi.rs`. The additive-only policy this project holds
//!   is about how the *schema* may evolve between versions so old clients keep
//!   working; it is not a licence for the server to emit fields no client can
//!   know exist, which is precisely how a hand-written Dart model ends up
//!   missing one.
//!
//! Coverage is enumerated, never assumed. Every operationId in the schema must
//! either be exercised below or appear in `UNCOVERED` with a reason, and an
//! entry in `UNCOVERED` that is stale (unknown, or actually covered) fails
//! too. Silence is the one outcome this test must never produce, because a
//! contract test that quietly skips an endpoint reads as assurance while
//! giving none.

mod openapi;
mod script;
mod verdict;
mod world;

use std::collections::BTreeSet;

use world::Contract;

/// Operations this test cannot drive, each with the reason. Anything not on
/// this list must be called.
const UNCOVERED: &[(&str, &str)] = &[(
    "connectWebSocket",
    "an upgrade, not a request/response: the only statuses it documents are 101 and \
     503 and neither carries a body. The frames that flow afterwards are exercised by \
     tests/ws.rs against a real socket.",
)];

#[tokio::test]
async fn responses_match_the_schema() {
    let mut contract = Contract::new().await;
    script::run(&mut contract).await;

    let documented = contract.operation_ids();
    let exempt: BTreeSet<String> = UNCOVERED.iter().map(|(id, _)| (*id).to_owned()).collect();
    let mut problems: Vec<String> = contract.problems().to_vec();

    for (id, reason) in UNCOVERED {
        assert!(
            documented.contains(*id),
            "UNCOVERED lists `{id}` ({reason}), which schema/openapi.yaml does not document; \
             delete the entry"
        );
        assert!(
            !contract.covered().contains(*id),
            "UNCOVERED lists `{id}` as impossible to drive, but the script drives it; \
             delete the entry"
        );
    }

    for id in documented.difference(contract.covered()) {
        if exempt.contains(id) {
            continue;
        }
        problems.push(format!(
            "{id} is documented in schema/openapi.yaml but nothing in \
             tests/response_contract/script.rs calls it, so no response of its has ever \
             been checked. Add a case, or add it to UNCOVERED with a reason."
        ));
    }

    problems.sort();
    problems.dedup();
    assert!(
        problems.is_empty(),
        "\n{} response(s) do not match schema/openapi.yaml:\n\n{}\n",
        problems.len(),
        problems.join("\n")
    );
}
