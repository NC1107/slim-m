// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//! Placing one object on a channel's canvas over HTTP, split across sibling
//! modules the `canvas_ops` shape once the single-file version crossed the
//! 500-line hard limit: `fixtures` is shared setup, `write` is every test.

mod fixtures;
#[path = "../support/mod.rs"]
mod support;
mod write;
