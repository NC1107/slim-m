// SPDX-License-Identifier: AGPL-3.0-only
//! `POST /channels/{id}/messages/bulk-delete-by-author`: selecting a raider's
//! messages by author and time window instead of naming up to 64 ids.
//!
//! Split into sibling modules the same shape `message_bulk_delete` already
//! uses: `harness` is the store, router, and request helpers every test
//! shares, `cases` is the tests themselves.

mod cases;
mod harness;
#[path = "../support/mod.rs"]
mod support;
