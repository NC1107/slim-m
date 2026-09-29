// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The profile card's line for what a member is listening to or playing.
///
/// Absent when there is none, like every other piece of the card. It reads
/// its own provider so the card's parent does not rebuild on a track change.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/presence_activity.dart';

class MemberProfileActivity extends ConsumerWidget {
  const MemberProfileActivity({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(memberActivityProvider(userId));
    if (activity == null) return const SizedBox.shrink();
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        0,
        AppSpacing.s12,
        AppSpacing.s8,
      ),
      child: Row(
        children: [
          Icon(activityIcon(activity.kind), size: 14, color: tokens.accent),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              describeActivity(activity),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
