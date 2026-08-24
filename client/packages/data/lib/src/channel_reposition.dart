// SPDX-License-Identifier: Apache-2.0
/// A pure reposition of a [Channel] for an optimistic reorder overlay.
library;

import 'package:drift/drift.dart' show Value;

import 'database.dart';

extension ChannelReposition on Channel {
  /// A copy placed at [position] under [categoryId] (null for the top level).
  ///
  /// Used to render a reorder this client is waiting on, before the server
  /// confirms it and the store is actually rewritten. The drift `Value` wrap a
  /// nullable `categoryId` needs in `copyWith` stays in the data layer here,
  /// rather than leaking into the widget that draws the overlay.
  Channel repositioned({String? categoryId, required int position}) =>
      copyWith(position: position, categoryId: Value(categoryId));
}
