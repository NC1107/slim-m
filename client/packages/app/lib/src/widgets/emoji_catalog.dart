// SPDX-License-Identifier: Apache-2.0
/// The emoji picker's data: which categories it shows, in what order, and
/// how a search query filters the catalog.
///
/// The `emojis` package (BSD-3, actively maintained, pure Dart, no Flutter
/// dependency) supplies every codepoint from its own bundled data. That data
/// lives inside the package's own source, never inside this repo, which is
/// what lets a picker exist at all under the hygiene gate that forbids an
/// emoji codepoint literal anywhere in `client/`.
library;

import 'package:emojis/emoji.dart';
import 'package:flutter/widgets.dart';
import 'package:slimm_design_system/design_system.dart';

/// One picker tab. [recent] has no catalog [EmojiGroup] behind it: it shows
/// whatever the caller's own history holds instead.
///
/// [EmojiGroup.component] (skin tone and hair style modifiers, which compose
/// onto a base emoji rather than standing in as a reaction on their own) has
/// deliberately no tab here.
enum EmojiCategory {
  recent,
  smileysEmotion,
  peopleBody,
  animalsNature,
  foodDrink,
  activities,
  travelPlaces,
  objects,
  symbols,
  flags,
}

/// The real categories, in picker order. Excludes [EmojiCategory.recent],
/// which the panel only shows once there is a history to show.
const List<EmojiCategory> emojiCategoriesInOrder = [
  EmojiCategory.smileysEmotion,
  EmojiCategory.peopleBody,
  EmojiCategory.animalsNature,
  EmojiCategory.foodDrink,
  EmojiCategory.activities,
  EmojiCategory.travelPlaces,
  EmojiCategory.objects,
  EmojiCategory.symbols,
  EmojiCategory.flags,
];

extension EmojiCategoryInfo on EmojiCategory {
  String get label => switch (this) {
        EmojiCategory.recent => 'Recently used',
        EmojiCategory.smileysEmotion => 'Smileys and emotion',
        EmojiCategory.peopleBody => 'People',
        EmojiCategory.animalsNature => 'Animals and nature',
        EmojiCategory.foodDrink => 'Food and drink',
        EmojiCategory.activities => 'Activities',
        EmojiCategory.travelPlaces => 'Travel and places',
        EmojiCategory.objects => 'Objects',
        EmojiCategory.symbols => 'Symbols',
        EmojiCategory.flags => 'Flags',
      };

  IconData get icon => switch (this) {
        EmojiCategory.recent => AppIcons.clock,
        EmojiCategory.smileysEmotion => AppIcons.smile,
        EmojiCategory.peopleBody => AppIcons.peopleBody,
        EmojiCategory.animalsNature => AppIcons.animalsNature,
        EmojiCategory.foodDrink => AppIcons.foodDrink,
        EmojiCategory.activities => AppIcons.activities,
        EmojiCategory.travelPlaces => AppIcons.travelPlaces,
        EmojiCategory.objects => AppIcons.objects,
        EmojiCategory.symbols => AppIcons.symbols,
        EmojiCategory.flags => AppIcons.flags,
      };

  /// The catalog group this tab draws from, or null for [recent].
  EmojiGroup? get group => switch (this) {
        EmojiCategory.recent => null,
        EmojiCategory.smileysEmotion => EmojiGroup.smileysEmotion,
        EmojiCategory.peopleBody => EmojiGroup.peopleBody,
        EmojiCategory.animalsNature => EmojiGroup.animalsNature,
        EmojiCategory.foodDrink => EmojiGroup.foodDrink,
        EmojiCategory.activities => EmojiGroup.activities,
        EmojiCategory.travelPlaces => EmojiGroup.travelPlaces,
        EmojiCategory.objects => EmojiGroup.objects,
        EmojiCategory.symbols => EmojiGroup.symbols,
        EmojiCategory.flags => EmojiGroup.flags,
      };
}

/// The full catalog once, with [EmojiGroup.component] dropped. A top-level
/// `final` initializes lazily on first read and stays cached after, so this
/// is computed once per app run rather than once per keystroke.
final List<Emoji> _catalog = Emoji.all()
    .where((emoji) => emoji.emojiGroup != EmojiGroup.component)
    .toList(growable: false);

List<Emoji> emojiForCategory(EmojiGroup group) =>
    _catalog.where((emoji) => emoji.emojiGroup == group).toList();

/// Substring match over name, short name, and keywords; empty for a blank
/// query rather than the whole catalog, so the caller knows to fall back to
/// the selected category instead.
List<Emoji> searchEmoji(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return _catalog
      .where((emoji) =>
          emoji.name.contains(q) ||
          emoji.shortName.contains(q) ||
          emoji.keywords.any((keyword) => keyword.contains(q)))
      .toList();
}

/// Resolves a recently-used shelf (plain emoji characters, as persisted by
/// `recentEmojiProvider`) back to full catalog entries, dropping any
/// character the catalog no longer recognises rather than showing a blank
/// tile for it.
List<Emoji> recentEmojiEntries(List<String> chars) => [
      for (final char in chars)
        if (Emoji.byChar(char) case final emoji?) emoji,
    ];
