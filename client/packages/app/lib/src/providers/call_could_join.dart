// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Who is online and could join a voice channel's call.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'member_presence.dart';
import 'presence_controller.dart';

/// Online people who can view [channelId], bots excluded, sorted by name.
///
/// Reads the same channel member list and presence the member pane already
/// shows, so it names nobody a viewer could not already see.
final callCouldJoinProvider = Provider.autoDispose
    .family<List<api.UserProfile>, String>((ref, channelId) {
      ref.watch(presenceSeedProvider(channelId));
      final members = ref.watch(channelMembersProvider(channelId));
      ref.watch(presenceControllerProvider.select(reachablePresenceKey));
      final presence = ref.read(presenceControllerProvider);
      return [
        for (final m in members.valueOrNull ?? const <api.UserProfile>[])
          if (!m.isBot && isReachablePresence(presenceOf(presence[m.id]))) m,
      ]..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
    });

/// The one line naming who could join, or null when nobody is online.
String? couldJoinLine(List<String> names) => switch (names.length) {
  0 => null,
  1 => '${names[0]} is online',
  2 => '${names[0]} and ${names[1]} are online',
  3 => '${names[0]}, ${names[1]} and 1 other are online',
  final n => '${names[0]}, ${names[1]} and ${n - 2} others are online',
};
