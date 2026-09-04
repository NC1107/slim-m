// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The list of overwrites already set on the channel
/// [ChannelOverwritesPane] is editing, split out to keep that file under
/// budget.
///
/// Fetched through `channelOverwritesProvider` and resolved against
/// `rolesProvider`/`membersProvider` for a name to show instead of a bare
/// id - the same two lists the picker sheets in
/// `overwrite_target_picker_sheets.dart` already draw from. Tapping a row
/// hands the raw overwrite back to the caller so the editor can pre-fill
/// from its allow/deny pair instead of opening at "Inherit" sight unseen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/member_presence.dart' show membersProvider;
import '../../widgets/settings_section_header.dart';

class CurrentOverwritesSection extends ConsumerWidget {
  const CurrentOverwritesSection({
    super.key,
    required this.channelId,
    required this.onSelect,
  });

  final String channelId;
  final void Function(api.ChannelOverwrite overwrite, String label) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overwrites = ref.watch(channelOverwritesProvider(channelId));
    final roles = ref.watch(rolesProvider).valueOrNull;
    final members = ref.watch(membersProvider).valueOrNull;

    return AppAsyncView<List<api.ChannelOverwrite>>(
      value: AppAsyncState(
        data: overwrites.valueOrNull,
        error: overwrites.error,
      ),
      center: false,
      errorMessage: 'Could not load this channel\'s current overwrites.',
      onRetry: () => ref.invalidate(channelOverwritesProvider(channelId)),
      isEmpty: (list) => list.isEmpty,
      emptyMessage: 'No overwrites set on this channel yet.',
      data: (context, list) => SettingsSectionCard(
        title: 'Current overwrites',
        description:
            'Tap one to edit it, pre-filled with what it already '
            'has set.',
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final overwrite in list)
            _OverwriteRow(
              overwrite: overwrite,
              label: _labelFor(overwrite, roles, members),
              onTap: () =>
                  onSelect(overwrite, _labelFor(overwrite, roles, members)),
            ),
        ],
      ),
    );
  }
}

String _labelFor(
  api.ChannelOverwrite overwrite,
  List<api.Role>? roles,
  List<api.UserProfile>? members,
) {
  if (overwrite.kind == api.OverwriteTarget.role) {
    return roles?.where((r) => r.id == overwrite.id).firstOrNull?.name ??
        'Unknown role';
  }
  return members?.where((m) => m.id == overwrite.id).firstOrNull?.displayName ??
      'Unknown member';
}

class _OverwriteRow extends StatelessWidget {
  const _OverwriteRow({
    required this.overwrite,
    required this.label,
    required this.onTap,
  });

  final api.ChannelOverwrite overwrite;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AppListRow(
    leading: Icon(
      overwrite.kind == api.OverwriteTarget.role
          ? AppIcons.shield
          : AppIcons.account,
    ),
    label: label,
    meta: _summary(_bitCount(overwrite.allow), _bitCount(overwrite.deny)),
    trailing: const Icon(AppIcons.chevronRight, size: AppSizes.icon16),
    onTap: onTap,
  );

  static String _summary(int allowCount, int denyCount) {
    if (allowCount == 0 && denyCount == 0) return 'Nothing set';
    final parts = <String>[
      if (allowCount > 0) '$allowCount allowed',
      if (denyCount > 0) '$denyCount denied',
    ];
    return parts.join(', ');
  }

  static int _bitCount(int value) {
    var count = 0;
    for (var remaining = value; remaining != 0; remaining >>= 1) {
      count += remaining & 1;
    }
    return count;
  }
}
