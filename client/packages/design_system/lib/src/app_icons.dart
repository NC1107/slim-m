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

  // Messaging.
  static const IconData send = LucideIcons.send;
  static const IconData edit = LucideIcons.pencil;
  static const IconData retry = LucideIcons.rotateCw;
  static const IconData pending = LucideIcons.clock;
  static const IconData failed = LucideIcons.circleAlert;
  static const IconData poll = LucideIcons.barChart2;
  static const IconData code = LucideIcons.code;
  static const IconData smile = LucideIcons.smile;

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

  // Severity and surfaces (callouts, menus, code blocks). Distinct shapes
  // (circle, triangle, sparkle, octagon) so a tone survives greyscale rather
  // than resting on colour alone.
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData highlight = LucideIcons.sparkles;
  static const IconData danger = LucideIcons.octagonAlert;
  static const IconData check = LucideIcons.check;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData copy = LucideIcons.copy;
}
