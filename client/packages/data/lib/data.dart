// SPDX-License-Identifier: Apache-2.0
/// The client's local store.
///
/// The store is the single source of truth: the UI observes it, and both
/// delivery routes (live WebSocket push and REST catch-up) write through it.
/// [MessageStore.applyMessage] is where idempotency and ordering are decided, so
/// the two routes can interleave, repeat, or overlap safely.
library;

export 'src/connection/connection.dart' show openSlimmDatabase;
export 'src/database.dart' show SlimmDatabase, Channel, Message;
export 'src/message_store.dart' show MessageStore;
