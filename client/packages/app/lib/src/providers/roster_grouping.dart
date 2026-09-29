// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// How the member pane sections its roster: one section per role, then
/// Online, Offline and Bots.
///
/// Roles are not hoist-flagged on the wire yet, so every role a member holds
/// as their highest one becomes a section, and only for members who are
/// online. `GET /roles` needs MANAGE_ROLES, so the section order is derived
/// from the members' own role lists (each is highest-position first) rather
/// than from positions, which keeps it identical for every viewer.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import 'member_presence.dart';
import 'presence_controller.dart';

/// Online members whose highest role is [roleId], listed under [name].
typedef RoleSection = ({
  String roleId,
  String name,
  List<api.UserProfile> members,
});

/// The roster split into the sections the pane shows, top to bottom.
class RosterGroups {
  const RosterGroups({
    this.roles = const [],
    this.online = const [],
    this.offline = const [],
    this.bots = const [],
  });

  final List<RoleSection> roles;
  final List<api.UserProfile> online;
  final List<api.UserProfile> offline;
  final List<api.UserProfile> bots;
}

/// The role a member is listed under, or null when they hold none.
///
/// Null too on a server that sends no ids, or names that do not line up with
/// them, since a section keyed on a guess would be worse than none.
({String id, String name})? topRoleOf(api.UserProfile member) {
  if (member.roleIds.isEmpty || member.roleIds.length != member.roles.length) {
    return null;
  }
  return (id: member.roleIds.first, name: member.roles.first);
}

/// Splits [members] into role sections, online, offline and bots, each
/// name-sorted. A member absent from [statusOf] counts as offline, the only
/// honest default when presence is unknown.
RosterGroups groupRoster(
  List<api.UserProfile> members,
  Map<String, AppPresence> statusOf,
) {
  final byRole = <String, List<api.UserProfile>>{};
  final roleNames = <String, String>{};
  final online = <api.UserProfile>[];
  final offline = <api.UserProfile>[];
  final bots = <api.UserProfile>[];
  for (final member in members) {
    if (member.isBot) {
      bots.add(member);
      continue;
    }
    final status = statusOf[member.id];
    if (status == null || !isReachablePresence(status)) {
      offline.add(member);
      continue;
    }
    final top = topRoleOf(member);
    if (top == null) {
      online.add(member);
      continue;
    }
    roleNames[top.id] = top.name;
    (byRole[top.id] ??= []).add(member);
  }
  int byName(api.UserProfile a, api.UserProfile b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  online.sort(byName);
  offline.sort(byName);
  bots.sort(byName);
  final order = _roleOrder(members);
  final sections = [
    for (final id in order)
      if (byRole.containsKey(id))
        (roleId: id, name: roleNames[id]!, members: byRole[id]!..sort(byName)),
  ];
  return RosterGroups(
    roles: sections,
    online: online,
    offline: offline,
    bots: bots,
  );
}

/// Every role id seen in [members], highest first. Each member's list is in
/// position order, so consecutive ids are precedence edges; roles no member
/// shares a list with are ordered by name.
List<String> _roleOrder(List<api.UserProfile> members) {
  final names = <String, String>{};
  final below = <String, Set<String>>{};
  final indegree = <String, int>{};
  for (final member in members) {
    if (topRoleOf(member) == null) continue;
    for (var i = 0; i < member.roleIds.length; i++) {
      final id = member.roleIds[i];
      names[id] = member.roles[i];
      indegree.putIfAbsent(id, () => 0);
      below.putIfAbsent(id, () => {});
      if (i == 0) continue;
      final above = member.roleIds[i - 1];
      if (below[above]!.add(id)) indegree[id] = indegree[id]! + 1;
    }
  }
  int byName(String a, String b) {
    final c = names[a]!.toLowerCase().compareTo(names[b]!.toLowerCase());
    return c != 0 ? c : a.compareTo(b);
  }

  final order = <String>[];
  final remaining = {...indegree.keys};
  while (remaining.isNotEmpty) {
    final ready = remaining.where((id) => indegree[id] == 0).toList();
    final pool = ready.isEmpty ? remaining.toList() : ready;
    final next = (pool..sort(byName)).first;
    remaining.remove(next);
    order.add(next);
    for (final id in below[next]!) {
      indegree[id] = indegree[id]! - 1;
    }
  }
  return order;
}

/// One row of the member pane's roster: a group heading or a member.
sealed class RosterEntry {
  const RosterEntry();
}

final class RosterGroupLabel extends RosterEntry {
  const RosterGroupLabel(this.text);
  final String text;
}

final class RosterMember extends RosterEntry {
  const RosterMember(this.profile);
  final api.UserProfile profile;
}

/// [groups] flattened into the rows the pane lays out, each non-empty group
/// as its heading followed by its members, so a lazy list builds only the
/// rows on screen. Bots come last whatever their presence.
List<RosterEntry> rosterEntries(RosterGroups groups) => [
  for (final section in groups.roles) ...[
    RosterGroupLabel('${section.name} · ${section.members.length}'),
    for (final m in section.members) RosterMember(m),
  ],
  if (groups.online.isNotEmpty) ...[
    RosterGroupLabel('Online · ${groups.online.length}'),
    for (final m in groups.online) RosterMember(m),
  ],
  if (groups.offline.isNotEmpty) ...[
    RosterGroupLabel('Offline · ${groups.offline.length}'),
    for (final m in groups.offline) RosterMember(m),
  ],
  if (groups.bots.isNotEmpty) ...[
    RosterGroupLabel('Bots · ${groups.bots.length}'),
    for (final m in groups.bots) RosterMember(m),
  ],
];

/// The pane's rows for [channelId]'s roster, rebuilt only when the roster or
/// who is reachable changes, so a selection toggle or a dot changing colour
/// does not regroup a large roster.
final rosterEntriesProvider = Provider.autoDispose
    .family<List<RosterEntry>, String?>((ref, channelId) {
      final members = channelId == null
          ? ref.watch(membersProvider)
          : ref.watch(channelMembersProvider(channelId));
      ref.watch(presenceControllerProvider.select(reachablePresenceKey));
      final presence = ref.read(presenceControllerProvider);
      final statusOf = {
        for (final entry in presence.entries)
          entry.key: presenceOf(entry.value),
      };
      return rosterEntries(groupRoster(members.valueOrNull ?? [], statusOf));
    });
