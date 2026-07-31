// SPDX-License-Identifier: AGPL-3.0-only
//! The canvas op stream's catch-up feed: `place` writes one op per placement,
//! the feed pages them densely, and `reset` fires on all three triggers.
//!
//! Split across sibling modules, the `response_contract` shape, once the
//! single-file version crossed the 500-line hard limit: `http_gate` is the
//! route wired end to end, `feed` is everything below it.

mod feed;
mod fixtures;
mod http_gate;
mod restore;
#[path = "../support/mod.rs"]
mod support;
mod write;
