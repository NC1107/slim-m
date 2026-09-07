// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Every module app this viewer may launch into a channel: `GET /modules/apps`.
/// An empty list means no installed and enabled module declares an `app`
/// extension point the caller holds the permission for - see
/// docs/decisions/0021-modules-and-the-dock.md's module-agnostic principle. The
/// composer offers these both in its apps menu and as a `/name` alias, and
/// [matchApp] is how it recognizes, on send, that a message is an app to launch.
///
/// Invalidated by the same module install/enable/disable and permission
/// grant/revoke events [slashCommandProvider] watches - the only things that
/// change what this answers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

final appLaunchProvider = FutureProvider.autoDispose<List<api.App>>(
  (ref) => ref.watch(apiProvider).listApps(),
);

/// A slash keyword for [app]: its module id, a slug already, so `/game-of-life`
/// launches it. Shown in the composer's `/` menu and matched by [matchApp].
String appSlashKeyword(api.App app) => app.moduleId;

/// The app [text] launches, or null when [text] is not `/name` for any app the
/// caller may launch. Like [matchSlashCommand] a launch is the whole message
/// (the `/` trigger only opens at offset zero); the keyword is the app's module
/// id, or its display name slugified, matched case-insensitively. Any argument
/// after the keyword is ignored: an app takes no launch argument.
api.App? matchApp(List<api.App> apps, String text) {
  final trimmed = text.trimLeft();
  if (!trimmed.startsWith('/')) return null;
  final body = trimmed.substring(1);
  final match = RegExp(r'\s').firstMatch(body);
  final name = (match == null ? body : body.substring(0, match.start))
      .toLowerCase();
  if (name.isEmpty) return null;
  for (final app in apps) {
    if (app.moduleId.toLowerCase() == name) return app;
    if (app.name.toLowerCase().replaceAll(' ', '-') == name) return app;
  }
  return null;
}
