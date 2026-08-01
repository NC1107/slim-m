// SPDX-License-Identifier: Apache-2.0
/// Opening a thread from a message.
///
/// A thread is an ordinary channel once opened (`GET /channels/{id}/messages`
/// and `POST` to send both work on it unchanged, exactly like a DM), so this
/// file does not give threads a parallel data model either - see
/// `providers/dms.dart`'s own doc comment for the precedent this follows.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

/// Display copy for a thread's local channel row: never sent or read on the
/// wire (the server stores a thread's own `name` as empty, mirroring a DM),
/// so this is the one place that substitution happens, the same shape
/// `channelFromDm` follows for a DM's name.
const String threadChannelName = 'Thread';

/// Opens (or reuses) the thread hanging off [messageId] in [channelId], and
/// gets it into the local store with an initial page of whatever it already
/// holds.
///
/// Unlike [openDirectMessage] (`providers/dms.dart`), this always fetches a
/// backfill page: a DM either has no history yet (freshly opened, nothing to
/// fetch) or was already synced through the ordinary periodic channel
/// refresh, since `GET /dms` lists it. A thread is excluded from every such
/// listing by design (`docs/decisions/0005-threads.md`), so re-opening one
/// that already has messages is the only chance this client gets to learn
/// about them before a live event happens to arrive.
///
/// Takes a [ProviderContainer] rather than a [WidgetRef], the same reason
/// [openDirectMessage] does: the message row that starts this can be
/// disposed (its menu closed) before the request answers.
Future<String> openThreadFromMessage(
  ProviderContainer container,
  String channelId,
  String messageId,
) async {
  final client = container.read(apiProvider);
  final thread = await client.openThread(
    channelId: channelId,
    messageId: messageId,
  );
  final store = await container.read(storeProvider.future);
  await store.upsertChannels([
    api.Channel(
      id: thread.id,
      name: threadChannelName,
      kind: thread.kind,
      createdAt: thread.createdAt,
      parentMessageId: thread.parentMessageId,
    ),
  ]);
  try {
    final recent = await client.listMessages(thread.id, limit: 50);
    await store.applyMessages(recent);
  } on api.ApiException {
    // Best effort: the transcript's own live socket or a later reopen corrects it.
  }
  return thread.id;
}
