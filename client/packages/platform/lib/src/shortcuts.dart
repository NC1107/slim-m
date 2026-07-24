// SPDX-License-Identifier: Apache-2.0
/// Keyboard shortcuts.
///
/// Bindings live in one table rather than scattered across widgets, which is
/// what makes them remappable at all: a user's override replaces an entry here
/// and every call site follows, because widgets bind to the *action*, never to
/// a key combination.
///
/// The modifier is chosen by platform on purpose. This is the one place where
/// the platform genuinely is the question, unlike layout, where width is.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Something the user can ask for, independent of how they ask.
enum AppAction {
  /// Jump to a channel by typing part of its name.
  quickSwitch,

  /// Move focus to the composer.
  focusComposer,

  /// Leave the current conversation, or close what is open.
  escape,

  /// Next and previous channel in the list.
  nextChannel,
  previousChannel,

  /// Open settings.
  openSettings;

  /// A human-readable name, for a keybinding screen.
  String get label => switch (this) {
        AppAction.quickSwitch => 'Quick switcher',
        AppAction.focusComposer => 'Focus the composer',
        AppAction.escape => 'Close or go back',
        AppAction.nextChannel => 'Next channel',
        AppAction.previousChannel => 'Previous channel',
        AppAction.openSettings => 'Open settings',
      };
}

/// The primary modifier: command on Apple platforms, control elsewhere. Using
/// control on macOS would collide with the system's own conventions and feel
/// wrong to anyone who uses a Mac.
bool get _useMeta =>
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.iOS;

SingleActivator _primary(LogicalKeyboardKey key, {bool shift = false}) =>
    SingleActivator(
      key,
      meta: _useMeta,
      control: !_useMeta,
      shift: shift,
    );

/// The bindings a user has not overridden.
Map<ShortcutActivator, AppAction> defaultBindings() => {
      _primary(LogicalKeyboardKey.keyK): AppAction.quickSwitch,
      _primary(LogicalKeyboardKey.keyL): AppAction.focusComposer,
      _primary(LogicalKeyboardKey.comma): AppAction.openSettings,
      const SingleActivator(LogicalKeyboardKey.escape): AppAction.escape,
      _primary(LogicalKeyboardKey.tab): AppAction.nextChannel,
      _primary(LogicalKeyboardKey.tab, shift: true): AppAction.previousChannel,
    };

/// The active bindings, defaults overlaid with a user's overrides.
///
/// An override that maps an action to nothing removes its shortcut entirely,
/// which someone using a screen reader or an alternative input device may well
/// want.
Map<ShortcutActivator, AppAction> resolveBindings({
  Map<AppAction, ShortcutActivator?> overrides = const {},
}) {
  final resolved = <ShortcutActivator, AppAction>{};
  final overridden = overrides.keys.toSet();

  for (final entry in defaultBindings().entries) {
    if (overridden.contains(entry.value)) continue;
    resolved[entry.key] = entry.value;
  }
  for (final entry in overrides.entries) {
    final activator = entry.value;
    if (activator != null) resolved[activator] = entry.key;
  }
  return resolved;
}
