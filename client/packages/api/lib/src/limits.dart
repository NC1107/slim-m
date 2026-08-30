// SPDX-License-Identifier: Apache-2.0
/// Wire-level bounds a caller needs before sending, not merely after a
/// rejection.
library;

/// Longest a single message's content may be, in characters.
///
/// Mirrors `MESSAGE_MAX_CHARS` in `crates/slimm-server/src/http/messages.rs`,
/// the same way `CLIENT_HEARTBEAT_INTERVAL` mirrors its Dart counterpart: two
/// constants agreeing by doc comment rather than by a shared source, because
/// there is no code generation between the two languages here (see
/// `schema/openapi.yaml`'s own header). If the server's limit ever changes,
/// this one has to change with it or the composer's counter and its refusal
/// to send drift from what the server actually enforces.
const kMessageMaxChars = 4000;

/// Longest a private user note may be, in characters, after trimming.
///
/// Mirrors `MAX_NOTE_CHARS` in `crates/slimm-server/src/http/user_notes.rs`;
/// see [kMessageMaxChars]'s own doc comment for why this is a mirrored
/// constant rather than a generated one.
const kUserNoteMaxChars = 500;
