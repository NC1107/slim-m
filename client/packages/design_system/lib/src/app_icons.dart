// SPDX-License-Identifier: Apache-2.0
/// The icon vocabulary.
///
/// Widgets reference these names, never an icon package directly, so the set can
/// be swapped in one file. Emoji are never interface chrome; they are user
/// content only (reactions), which a CI grep enforces.
library;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

abstract final class AppIcons {
  // Navigation and structure.
  static const IconData hash = LucideIcons.hash;
  static const IconData voice = LucideIcons.volume2;
  static const IconData settings = LucideIcons.settings;
  static const IconData members = LucideIcons.users;
  static const IconData back = LucideIcons.arrowLeft;
  static const IconData add = LucideIcons.plus;
  static const IconData search = LucideIcons.search;
  static const IconData info = LucideIcons.info;
  static const IconData chevronDown = LucideIcons.chevronDown;
  static const IconData pin = LucideIcons.pin;

  /// The trigger for a per-row overflow menu (a channel's manage sheet).
  static const IconData moreVertical = LucideIcons.moreVertical;

  // Messaging.
  static const IconData send = LucideIcons.send;
  static const IconData edit = LucideIcons.pencil;
  static const IconData retry = LucideIcons.rotateCw;
  static const IconData pending = LucideIcons.clock;
  static const IconData failed = LucideIcons.circleAlert;
  static const IconData poll = LucideIcons.barChart2;
  static const IconData code = LucideIcons.code;
  static const IconData smile = LucideIcons.smile;

  /// The emoji picker's category tabs. `smileysEmotion` reuses [smile] above
  /// and `recent` reuses [clock] below; these eight cover the rest of the
  /// `emojis` package's [EmojiGroup] set.
  static const IconData peopleBody = LucideIcons.footprints;
  static const IconData animalsNature = LucideIcons.pawPrint;
  static const IconData foodDrink = LucideIcons.utensils;
  static const IconData activities = LucideIcons.volleyball;
  static const IconData travelPlaces = LucideIcons.planeTakeoff;
  static const IconData objects = LucideIcons.lightbulb;
  static const IconData symbols = LucideIcons.asterisk;
  static const IconData flags = LucideIcons.flag;

  /// A staleness cue distinct from [pending]: the same glyph, a different
  /// role (an expiring device or invite rather than an in-flight send), kept
  /// as its own name so the two are never conflated at a call site.
  static const IconData clock = LucideIcons.clock;

  // Calls and canvas, wired up in later phases.
  static const IconData mic = LucideIcons.mic;
  static const IconData micOff = LucideIcons.micOff;
  static const IconData headphones = LucideIcons.headphones;
  static const IconData camera = LucideIcons.video;
  static const IconData screenShare = LucideIcons.monitorUp;
  static const IconData leaveCall = LucideIcons.phoneOff;
  static const IconData canvas = LucideIcons.pencilRuler;

  // Account.
  static const IconData signOut = LucideIcons.logOut;
  static const IconData account = LucideIcons.circleUser;

  // Notifications.
  static const IconData notificationsOn = LucideIcons.bell;
  static const IconData notificationsOff = LucideIcons.bellOff;

  /// Severity and surfaces (callouts, menus, code blocks). Distinct shapes
  /// (circle, triangle, sparkle, octagon) so a tone survives greyscale rather
  /// than resting on colour alone.
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData highlight = LucideIcons.sparkles;
  static const IconData danger = LucideIcons.octagonAlert;
  static const IconData check = LucideIcons.check;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData copy = LucideIcons.copy;

  // Moderation and administration: the reports queue, invite management,
  // roles, and channel permission overwrites.
  static const IconData report = LucideIcons.messageSquareWarning;
  static const IconData invite = LucideIcons.mailPlus;
  static const IconData shield = LucideIcons.shield;
  static const IconData delete = LucideIcons.trash2;
  static const IconData revoke = LucideIcons.ban;
  static const IconData dismiss = LucideIcons.x;
  static const IconData assignRole = LucideIcons.userCog;
  static const IconData permissions = LucideIcons.lock;
}
