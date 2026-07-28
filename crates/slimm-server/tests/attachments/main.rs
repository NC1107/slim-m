// SPDX-License-Identifier: AGPL-3.0-only
//! HTTP integration tests for attachments.
//!
//! Split by which stage of an attachment's life the test pins, since that is
//! also which handler decides it: [`uploading`] covers what `POST /attachments`
//! accepts, [`serving`] what `GET /attachments/{id}` answers (the permission
//! gate first of all, since an unguessable hex id is not access control), and
//! [`binding`] an attachment's relationship to the message carrying it.
//!
//! [`filenames`] is the one exception, and deliberately so: the filename is
//! caller-controlled text that crosses all three stages, so what it can reach
//! is only visible as a round trip. [`fixtures`] is the temp database, router
//! and request builders they all share.

mod binding;
mod filenames;
mod fixtures;
mod serving;
mod uploading;

#[path = "../support/mod.rs"]
mod support;
