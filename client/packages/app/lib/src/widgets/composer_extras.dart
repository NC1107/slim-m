// SPDX-License-Identifier: Apache-2.0
/// The composer's smaller pieces: a staged attachment's removable chip, and
/// the "who is typing" line that fills its reserved hint-row slot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/typing_controller.dart';
import 'member_pane.dart';

/// One attachment uploaded but not yet sent. The whole chip is the tap
/// target for removing it, since [AppChip.operator] is deliberately
/// non-interactive and there is no dedicated "remove" glyph in
/// [AppIcons] to reach for instead.
class StagedAttachmentChip extends StatelessWidget {
  const StagedAttachmentChip({
    super.key,
    required this.filename,
    required this.onRemove,
  });

  final String filename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      label: 'Remove attachment $filename',
      button: true,
      child: GestureDetector(
        onTap: onRemove,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            border: Border.all(color: tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                filename,
                style: AppText.caption.copyWith(color: tokens.textPrimary),
              ),
              const SizedBox(width: AppSpacing.s4),
              Text(
                'x',
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Who is typing in this channel, from real `typing.started`/`typing.stopped`
/// events. Receive-only: see `providers/typing_controller.dart` for why this
/// client has nothing to send one back with yet.
class TypingIndicator extends ConsumerWidget {
  const TypingIndicator({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typingIds = ref.watch(typingControllerProvider(channelId));
    if (typingIds.isEmpty) return const SizedBox.shrink();

    final tokens = Theme.of(context).extension<AppTokens>()!;
    final members =
        ref.watch(membersProvider).valueOrNull ?? const <api.UserProfile>[];
    String nameFor(String id) => members
        .firstWhere(
          (m) => m.id == id,
          orElse: () => api.UserProfile(
            id: id,
            username: id,
            displayName: 'Someone',
            createdAt: 0,
          ),
        )
        .displayName;

    final names = typingIds.map(nameFor).toList()..sort();
    final label = names.length == 1
        ? '${names.first} is typing…'
        : '${names.join(', ')} are typing…';

    return Text(
      label,
      style: AppText.code.copyWith(color: tokens.textSecondary),
    );
  }
}
