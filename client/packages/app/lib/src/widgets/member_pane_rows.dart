// SPDX-License-Identifier: Apache-2.0
/// The rows the member pane is built out of: a group heading, a member, and
/// what an empty result says.
///
/// Split from `member_pane.dart` when the search box pushed it past the
/// review budget. The pane keeps what decides *which* members show; this
/// keeps what decides how one of them draws, and the two change for
/// different reasons.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import 'member_profile.dart';
import 'user_avatar.dart';

class MemberGroupLabel extends StatelessWidget {
  const MemberGroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      // A heading in its natural case, for the same reason the rail's are.
      child: Semantics(
        container: true,
        header: true,
        label: text,
        child: ExcludeSemantics(
          child: Text(
            text.toUpperCase(),
            style: AppText.label.copyWith(color: tokens.textSecondary),
          ),
        ),
      ),
    );
  }
}

/// How a presence state is spoken, since on screen it is only a dot's colour
/// and silhouette.
///
/// Hidden is deliberately absent: it renders for the one person appearing
/// offline, and naming it aloud beside their own name tells them nothing they
/// did not choose.
String? _presenceDescription(AppPresence status) => switch (status) {
  AppPresence.online => 'online',
  AppPresence.away => 'away',
  AppPresence.dnd => 'do not disturb',
  AppPresence.offline => 'offline',
  AppPresence.hidden => null,
};

/// A row is muted (dimmed, per [AppListRow.muted]) only once fully offline;
/// away and do-not-disturb still read as present, matching the grouping
/// rule the pane applies.
///
/// A right-click reaches the same profile popover a tap already does, rather
/// than a second, narrower menu: every verb this row could offer already
/// lives there, gated exactly as it already is.
class MemberRow extends ConsumerWidget {
  const MemberRow({
    required this.profile,
    required this.status,
    required this.isSelf,
    super.key,
  });

  final api.UserProfile profile;
  final AppPresence status;

  /// Nothing opens a DM with yourself: `POST /dms/{userId}` has no concept
  /// of one, and a self-conversation would just be a second copy of the
  /// notes only you would ever see.
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Only the first: a row that grew with role count would push the name out of a 236px pane.
    final badge = profile.roles.isEmpty ? null : profile.roles.first;

    void open() => unawaited(
      showMemberProfile(context, ref, profile: profile, status: status),
    );

    final row = AppListRow(
      // Taller than a channel row: a 26px avatar's corner status dot crops at the default height.
      height: 36,
      label: profile.displayName,
      muted: status == AppPresence.offline,
      // On screen presence is only a dot and an opacity; this is how it is spoken.
      stateDescription: _presenceDescription(status),
      trailing: badge == null
          ? null
          : AppBadge(variant: AppBadgeVariant.role, label: badge),
      leading: UserAvatar(
        userId: profile.id,
        avatarUpdatedAt: profile.avatarUpdatedAt,
        name: profile.displayName,
        size: 26,
        status: status,
      ),
      // Opens the profile, which is where every verb about a member lives now.
      onTap: open,
    );

    // AppListRow is deliberately single-line and fixed-height, so a status is a caption stacked beneath it, not a change to that row.
    final content = profile.statusText == null
        ? row
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row,
              Padding(
                padding: const EdgeInsets.only(
                  left: AppSpacing.s8 + 26 + AppSpacing.s8,
                  right: AppSpacing.s8,
                  bottom: AppSpacing.s4,
                ),
                child: Text(
                  profile.statusText!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ),
            ],
          );

    return GestureDetector(onSecondaryTapDown: (_) => open(), child: content);
  }
}

/// What a search that matched nobody shows, so an empty pane reads as an
/// answer rather than as a roster that failed to load.
class MemberEmptyResult extends StatelessWidget {
  const MemberEmptyResult({required this.query, super.key});

  final String query;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s16,
      ),
      child: Text(
        query.trim().isEmpty ? 'No members yet' : 'Nobody matches "$query"',
        style: AppText.body.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}
