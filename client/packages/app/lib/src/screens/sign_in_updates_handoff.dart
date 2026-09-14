// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Where a brand-new desktop account goes after it is created: the one
/// question about automatic updates, asked once (decision 0025).
///
/// A file of its own because `sign_in_screen.dart` sits at its size ceiling,
/// and because this is a handoff out of signing in rather than part of it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_platform/platform.dart';

import '../providers/auto_update_preference.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';

/// Sends a just-created desktop account to the updates question, unless it
/// has already been answered.
///
/// Only [created] accounts, because an install with a session never passes
/// back through sign-in, and the splash asks those instead. Only desktop,
/// because a store build and the web page are updated by the store and the
/// browser. Everything else falls through to the router's own redirect,
/// which lands on the channels.
Future<void> askAboutUpdatesAfterSignUp(
  BuildContext context,
  WidgetRef ref, {
  required bool created,
}) async {
  if (!created || !isDesktopHost) return;
  final prefs = await ref.read(preferencesProvider.future);
  if (loadAutoUpdatePreference(prefs) != null) return;
  if (context.mounted) context.go(Routes.updatesChoice);
}
