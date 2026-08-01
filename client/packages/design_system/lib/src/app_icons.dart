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
  static const IconData hash = LucideIcons.hash300;
  static const IconData voice = LucideIcons.volume2300;
  static const IconData settings = LucideIcons.settings300;
  static const IconData members = LucideIcons.users300;

  /// The collapsible channel rail, drawn as a panel rather than a hamburger:
  /// it toggles one region of a visible layout rather than opening a drawer.
  static const IconData sidebar = LucideIcons.panelLeft300;
  static const IconData back = LucideIcons.arrowLeft300;
  static const IconData add = LucideIcons.plus300;
  static const IconData search = LucideIcons.search300;
  static const IconData info = LucideIcons.info300;
  static const IconData chevronDown = LucideIcons.chevronDown300;
  static const IconData pin = LucideIcons.pin300;

  /// The trigger for a per-row overflow menu (a channel's manage sheet).
  static const IconData moreVertical = LucideIcons.moreVertical300;

  // Messaging.
  static const IconData send = LucideIcons.send300;
  static const IconData edit = LucideIcons.pencil300;
  static const IconData retry = LucideIcons.rotateCw300;
  static const IconData pending = LucideIcons.clock300;
  static const IconData failed = LucideIcons.circleAlert300;
  static const IconData poll = LucideIcons.barChart2300;
  static const IconData code = LucideIcons.code300;
  static const IconData smile = LucideIcons.smile300;

  /// The emoji picker's category tabs. `smileysEmotion` reuses [smile] above
  /// and `recent` reuses [clock] below; these eight cover the rest of the
  /// `emojis` package's [EmojiGroup] set.
  static const IconData peopleBody = LucideIcons.footprints300;
  static const IconData animalsNature = LucideIcons.pawPrint300;
  static const IconData foodDrink = LucideIcons.utensils300;
  static const IconData activities = LucideIcons.volleyball300;
  static const IconData travelPlaces = LucideIcons.planeTakeoff300;
  static const IconData objects = LucideIcons.lightbulb300;
  static const IconData symbols = LucideIcons.asterisk300;
  static const IconData flags = LucideIcons.flag300;

  /// The picker's tab for the deployment's own uploaded emoji, and the
  /// placeholder a tile falls back to when that image cannot be fetched.
  static const IconData customEmoji = LucideIcons.sticker300;
  static const IconData imageMissing = LucideIcons.imageOff300;

  /// A picked image, once there is one to replace rather than choose fresh.
  static const IconData image = LucideIcons.image300;

  /// A staleness cue distinct from [pending]: the same glyph, a different
  /// role (an expiring device or invite rather than an in-flight send), kept
  /// as its own name so the two are never conflated at a call site.
  static const IconData clock = LucideIcons.clock300;

  // Calls and canvas, wired up in later phases.
  static const IconData mic = LucideIcons.mic300;
  static const IconData micOff = LucideIcons.micOff300;
  static const IconData headphones = LucideIcons.headphones300;

  /// Hearing one person, and not hearing them. Distinct from [mic]/[micOff],
  /// which are about your own microphone: these two are about what reaches
  /// your ears, so a call site that confuses them says the opposite thing.
  static const IconData speaker = LucideIcons.volume2300;
  static const IconData speakerOff = LucideIcons.volumeX300;
  static const IconData camera = LucideIcons.video300;
  static const IconData cameraOff = LucideIcons.videoOff300;
  static const IconData screenShare = LucideIcons.monitorUp300;
  static const IconData leaveCall = LucideIcons.phoneOff300;
  static const IconData canvas = LucideIcons.pencilRuler300;

  /// The canvas's own draw/erase toggle. Distinct constants from [edit] even
  /// though [pen] shares its glyph, since one names a message action and the
  /// other a drawing tool - a future change to one must not silently retint
  /// the other.
  static const IconData pen = LucideIcons.pencil300;
  static const IconData eraser = LucideIcons.eraser300;
  static const IconData undo = LucideIcons.undo2300;

  // Account.
  static const IconData signOut = LucideIcons.logOut300;
  static const IconData account = LucideIcons.circleUser300;

  /// The personal space: your own notes, not another person's avatar.
  static const IconData notebook = LucideIcons.notebookPen300;

  // Notifications.
  static const IconData notificationsOn = LucideIcons.bell300;
  static const IconData notificationsOff = LucideIcons.bellOff300;

  /// Severity and surfaces (callouts, menus, code blocks). Distinct shapes
  /// (circle, triangle, sparkle, octagon) so a tone survives greyscale rather
  /// than resting on colour alone.
  static const IconData warning = LucideIcons.triangleAlert300;
  static const IconData highlight = LucideIcons.sparkles300;
  static const IconData danger = LucideIcons.octagonAlert300;
  static const IconData check = LucideIcons.check300;
  static const IconData chevronRight = LucideIcons.chevronRight300;
  static const IconData copy = LucideIcons.copy300;

  /// A fourth, distinct shape for "not known", never to be confused with
  /// [danger]'s "known not to work".
  static const IconData unknown = LucideIcons.circleHelp300;

  // Moderation and administration: the reports queue, invite management,
  // roles, and channel permission overwrites.
  static const IconData report = LucideIcons.messageSquareWarning300;
  static const IconData invite = LucideIcons.mailPlus300;
  static const IconData shield = LucideIcons.shield300;

  /// A server that offers no reporting or blocking. Struck through, so "no
  /// recourse here" reads without colour, the same rule the severity icons
  /// above follow.
  static const IconData shieldOff = LucideIcons.shieldOff300;

  static const IconData delete = LucideIcons.trash2300;
  static const IconData revoke = LucideIcons.ban300;
  static const IconData dismiss = LucideIcons.x300;
  static const IconData assignRole = LucideIcons.userCog300;
  static const IconData permissions = LucideIcons.lock300;

  /// Removing a row from a personal list view rather than deleting anything:
  /// distinct from [delete], which destroys the thing itself.
  static const IconData removeFromList = LucideIcons.listX300;
}
