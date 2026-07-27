// SPDX-License-Identifier: Apache-2.0
/// Data for the moderation and administration screens: the reports queue,
/// invite management, roles, and channel permission overwrites.
///
/// Each list is a plain autoDispose future, matching [devicesProvider] and
/// [blocksProvider] in `settings_screen.dart`: nothing here is long-lived
/// state, so a screen refetches on entry and a mutation invalidates the one
/// list it touched.
///
/// The member list for the role-assignment picker is deliberately not here: it
/// is `membersProvider` from `widgets/member_pane.dart`, reused rather than
/// redefined, because it is the same `GET /members` page the rail header and
/// member pane already show and a second copy would invalidate independently
/// of theirs.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

/// The caller's own base (deployment-level) permission bitmask, or 0 while
/// [meProvider] is loading or failed: every gate here reads as "show
/// nothing" rather than "show everything" until proven otherwise.
final myPermissionsProvider = Provider<int>(
  (ref) => ref.watch(meProvider).valueOrNull?.permissions ?? 0,
);

/// The open moderation queue, oldest first.
final openReportsProvider = FutureProvider.autoDispose<List<api.Report>>(
  (ref) => ref.watch(apiProvider).listOpenReports(),
);

/// Every invite, in the order the server returns them.
final invitesProvider = FutureProvider.autoDispose<List<api.Invite>>(
  (ref) => ref.watch(apiProvider).listInvites(),
);

/// Every role.
final rolesProvider = FutureProvider.autoDispose<List<api.Role>>(
  (ref) => ref.watch(apiProvider).listRoles(),
);

/// Every custom emoji in the deployment, oldest first.
///
/// The one list, not the administration screen's own: `customEmojiIndexProvider`
/// in `emoji_catalog_provider.dart` reads it too, so uploading or removing one
/// here is what makes the next message render (or stop rendering) it. Two
/// providers over `GET /emoji` would leave a freshly uploaded emoji
/// unrenderable until relaunch.
final customEmojiProvider = FutureProvider.autoDispose<List<api.CustomEmoji>>(
  (ref) => ref.watch(apiProvider).listCustomEmoji(),
);
