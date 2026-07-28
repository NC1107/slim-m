// SPDX-License-Identifier: Apache-2.0
/// The deployment's member roster and live presence for it.
///
/// Split out of `widgets/member_pane.dart` to separate the data (this file)
/// from its rendering; most of this file's callers only ever wanted
/// [membersProvider], never anything about how the pane itself draws a row.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import 'live_events.dart';
import 'presence_controller.dart';
import 'providers.dart';

/// The deployment's members. Real endpoint, real data.
final membersProvider = FutureProvider.autoDispose<List<api.UserProfile>>(
  (ref) => ref.watch(apiProvider).listMembers(),
);

/// Seeds live presence for the resolved member list. A trigger, not a data
/// source in its own right: `AppMemberPane` watches this purely to start it,
/// and reads the actual statuses back from [presenceControllerProvider].
/// `autoDispose` and depending on the (also `autoDispose`) [membersProvider]
/// keeps this from outliving the pane, unlike [presenceControllerProvider]
/// itself, which is worth keeping warm for the rest of the session.
final presenceSeedProvider = FutureProvider.autoDispose<void>((ref) async {
  final members = await ref.watch(membersProvider.future);
  await ref
      .read(presenceControllerProvider.notifier)
      .refresh(members.map((m) => m.id));
});

/// Mirrors `MEMBERS_MAX_LIMIT` in `crates/slimm-server/src/http/users.rs`.
/// Below it, an unknown id means a stale cache; at or above it, an unknown
/// id is normal (a member off this page), so it must not force a refetch.
const _memberPageCeiling = 200;

/// Coalesces a burst of joins (or one join's presence-then-message pair)
/// into a single refetch rather than one per event.
const _rosterKeepAliveDebounce = Duration(milliseconds: 500);

/// There is no `MemberJoined` event (`hub.rs` has no such `Event` variant),
/// so [membersProvider] never notices a new member on its own. This infers
/// a join from what one already produces on the live socket - a presence
/// frame, or, failing that, the author id on a first message - and
/// invalidates the cached roster so the pane catches up without a reload.
final memberRosterKeepAliveProvider = Provider.autoDispose<void>((ref) {
  Timer? debounce;
  final sub = ref.read(liveEventsProvider).listen((event) {
    final candidateId = switch (event) {
      api.PresenceChanged(:final userId) => userId,
      api.MessageCreated(:final message) => message.authorId,
      _ => null,
    };
    if (candidateId == null) return;

    final members = ref.read(membersProvider).valueOrNull;
    // No cached roster yet, or a full page: neither says the id is a stale gap.
    if (members == null || members.length >= _memberPageCeiling) return;
    if (members.any((m) => m.id == candidateId)) return;

    debounce?.cancel();
    debounce = Timer(_rosterKeepAliveDebounce, () {
      ref.invalidate(membersProvider);
    });
  });
  ref.onDispose(() {
    debounce?.cancel();
    unawaited(sub.cancel());
  });
});

/// The design-system status a server [api.PresenceState] renders as. Both
/// [PresenceState.away] and [PresenceState.dnd] still group under "online"
/// below (see [groupMembersByPresence]): each is reachable in some capacity,
/// which is the distinction that bucket exists to draw, and the row itself
/// still shows the more specific dot shape/colour.
AppPresence presenceOf(api.PresenceState? state) => switch (state) {
  api.PresenceState.online => AppPresence.online,
  api.PresenceState.away => AppPresence.away,
  api.PresenceState.dnd => AppPresence.dnd,
  api.PresenceState.offline || null => AppPresence.offline,
};

/// Splits and sorts [members] by presence. A member absent from [statusOf]
/// counts as offline, which is the only honest default when presence is
/// unknown rather than assumed online. Away and do-not-disturb both count as
/// "online" for grouping purposes: both are a live, connected session, just
/// with a status layered on top, and grouping either under "Offline" would
/// read as a lie the row's own presence dot then has to contradict.
({List<api.UserProfile> online, List<api.UserProfile> offline})
groupMembersByPresence(
  List<api.UserProfile> members,
  Map<String, AppPresence> statusOf,
) {
  final online = <api.UserProfile>[];
  final offline = <api.UserProfile>[];
  for (final member in members) {
    final status = statusOf[member.id];
    final isOnlineGroup =
        status == AppPresence.online ||
        status == AppPresence.away ||
        status == AppPresence.dnd;
    (isOnlineGroup ? online : offline).add(member);
  }
  int byName(api.UserProfile a, api.UserProfile b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  online.sort(byName);
  offline.sort(byName);
  return (online: online, offline: offline);
}
