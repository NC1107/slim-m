// SPDX-License-Identifier: Apache-2.0
/// Channel category reads and writes, split out of `message_store.dart` for
/// the file budget. A category is not a channel and is replaced on its own
/// path here, never through [MessageStore.replaceChannels] - see
/// docs/decisions/0006-channel-categories.md.
library;

import 'package:drift/drift.dart';
import 'package:slimm_api/api.dart' as api;

import 'database.dart';
import 'message_store.dart';

extension CategoryStore on MessageStore {
  /// Watches every live category, in display order - the same "position,
  /// then id" ordering the server's own `list_categories` applies.
  Stream<List<ChannelCategoryRow>> watchCategories() {
    final query = db.select(db.channelCategories)
      ..orderBy([(c) => OrderingTerm(expression: c.position)]);
    return query.watch();
  }

  /// [watchCategories]'s own snapshot, for a caller that wants today's list
  /// once rather than a subscription it would only ever read one value from.
  Future<List<ChannelCategoryRow>> allCategories() {
    final query = db.select(db.channelCategories)
      ..orderBy([(c) => OrderingTerm(expression: c.position)]);
    return query.get();
  }

  /// Replaces the whole known category list with exactly what the server
  /// returned. Its own replace path, never shared with [MessageStore.
  /// replaceChannels]: a category is not a channel and never appears in that
  /// list, so pruning it there would delete every category on the very
  /// first channel refresh.
  Future<void> replaceCategories(List<api.ChannelCategory> categories) async {
    await db.transaction(() async {
      await db.batch((batch) {
        for (final category in categories) {
          batch.insert(
            db.channelCategories,
            ChannelCategoriesCompanion.insert(
              id: category.id,
              name: category.name,
              position: Value(category.position),
            ),
            onConflict: DoUpdate(
              (_) => ChannelCategoriesCompanion.custom(
                name: Variable(category.name),
                position: Variable(category.position),
              ),
            ),
          );
        }
      });
      final keep = categories.map((c) => c.id).toSet();
      await (db.delete(db.channelCategories)..where((c) => c.id.isNotIn(keep)))
          .go();
    });
  }

  /// Inserts or updates a single category, the way the categories screen
  /// applies its own create/rename/reposition immediately rather than
  /// waiting on the `CategoryChanged` live event to round-trip back to this
  /// same client - the same instant-feedback shape
  /// `create_channel_sheet.dart` already uses for a freshly created channel.
  Future<void> upsertCategory(api.ChannelCategory category) {
    return db.into(db.channelCategories).insertOnConflictUpdate(
          ChannelCategoriesCompanion.insert(
            id: category.id,
            name: category.name,
            position: Value(category.position),
          ),
        );
  }

  /// Removes one category locally, the immediate-feedback counterpart to
  /// [upsertCategory]. Never touches [Channels]: a category's own delete
  /// already uncategorises its channels server-side, and the next channel
  /// refresh (already triggered by the same `CategoryChanged` event) is what
  /// picks that up locally.
  Future<void> removeCategory(String categoryId) =>
      (db.delete(db.channelCategories)
            ..where(
              (c) => c.id.equals(categoryId),
            ))
          .go();
}
