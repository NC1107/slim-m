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
/// is `membersProvider` from `member_presence.dart`, reused rather than
/// redefined, because it is the same `GET /members` page the rail header and
/// member pane already show and a second copy would invalidate independently
/// of theirs.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'channel_permissions.dart';
import 'live_events.dart';
import 'providers.dart';

/// The caller's own base (deployment-level) permission bitmask, or 0 while
/// [meProvider] is loading or failed: every gate here reads as "show
/// nothing" rather than "show everything" until proven otherwise.
final myPermissionsProvider = Provider<int>(
  (ref) => ref.watch(meProvider).valueOrNull?.permissions ?? 0,
);

/// Every invite, in the order the server returns them.
final invitesProvider = FutureProvider.autoDispose<List<api.Invite>>(
  (ref) => ref.watch(apiProvider).listInvites(),
);

/// Everyone removed from the Space, newest first. The only list that still
/// names them: `GET /members` deliberately drops them.
final removedMembersProvider =
    FutureProvider.autoDispose<List<api.SpaceRemoval>>(
      (ref) => ref.watch(apiProvider).listRemovedMembers(),
    );

/// Every role.
final rolesProvider = FutureProvider.autoDispose<List<api.Role>>(
  (ref) => ref.watch(apiProvider).listRoles(),
);

/// Refetches [rolesProvider] and [meProvider] when a role's own definition
/// changes or a member's assignment does: either can change what a role
/// means for whoever is looking at this screen right now, and the caller's
/// own permissions besides. Watched by `HomeShell` for the whole session -
/// its only watch site used to be [RolesScreen], a MANAGE_ROLES-gated modal
/// never co-mounted with any consumer of what this invalidates, so for an
/// ordinary user none of it ever ran and a permission revoked mid-session
/// stayed visibly offered until renavigation. [RolesScreen] keeps its own
/// watch as documentation of the dependency, not as the thing keeping this
/// alive.
///
/// Also the one place [channelPermissionsProvider] and
/// [myVisibleChannelsProvider] are invalidated - see
/// docs/decisions/0011-per-channel-permissions.md. A role or role-assignment
/// change invalidates both bare, since either can change what the caller can
/// do (and see) in every channel at once; a self [api.MemberTimeoutChanged]
/// does the same and additionally refreshes [meProvider], closing the gap
/// where a moderator timed out mid-session kept a stale reading until some
/// unrelated refetch; an [api.OverwriteChanged] invalidates only the one
/// channel's permissions it names, plus the visible list, since an overwrite
/// can grant or revoke VIEW_CHANNEL and so change the list's membership.
final roleChangeWatcherProvider = Provider.autoDispose<void>((ref) {
  final selfId = ref.read(sessionProvider).tokens?.userId;
  // ref.invalidate on a never-watched provider mounts and fetches it.
  void refreshVisibleChannels() {
    if (ref.exists(myVisibleChannelsProvider)) {
      ref.invalidate(myVisibleChannelsProvider);
    }
  }

  final sub = ref.read(liveEventsProvider).listen((event) {
    if (event is api.RoleChanged || event is api.MemberRoleChanged) {
      ref.invalidate(rolesProvider);
      ref.invalidate(meProvider);
      ref.invalidate(channelPermissionsProvider);
      refreshVisibleChannels();
    } else if (event is api.MemberTimeoutChanged && event.userId == selfId) {
      ref.invalidate(meProvider);
      ref.invalidate(channelPermissionsProvider);
      refreshVisibleChannels();
    } else if (event is api.OverwriteChanged) {
      ref.invalidate(channelPermissionsProvider(event.channelId));
      refreshVisibleChannels();
    }
  });
  ref.onDispose(() => unawaited(sub.cancel()));
});

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

/// The Space usage analytics toggle and, while it is on, its stats. Off by
/// default; see `docs/decisions/0008-space-analytics.md` and
/// `screens/admin/analytics_screen.dart`.
final spaceAnalyticsProvider = FutureProvider.autoDispose<api.SpaceAnalytics>(
  (ref) => ref.watch(apiProvider).spaceAnalytics(),
);

/// The message retention window in days, `0` meaning keep forever - the
/// default, and what every deployment keeps until an admin sets one.
final spaceRetentionProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(apiProvider).spaceMessageRetentionDays(),
);

/// The per-channel canvas object cap, applied to every client. The default a
/// deployment keeps until an admin sets one is 20000; see
/// `screens/admin/canvas_cap_section.dart`.
final spaceCanvasCapProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(apiProvider).spaceCanvasObjectCap(),
);

/// The screen-share resolution ceiling, applied to every client's own
/// capture and publish parameters - see `screen_share_control.dart`. The
/// default a deployment keeps until an admin sets one is 2160; see
/// `screens/admin/screen_share_cap_section.dart`.
final spaceScreenShareCeilingProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.watch(apiProvider).spaceScreenShareMaxHeight(),
);
