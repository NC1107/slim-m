// SPDX-License-Identifier: Apache-2.0
/// The centre column's channel header: name, topic, pin pill, and the two
/// toggles that live beside it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/pins_controller.dart';
import 'member_pane.dart';
import 'pinned_messages_sheet.dart';

class ChannelHeader extends ConsumerWidget {
  const ChannelHeader({
    super.key,
    required this.channelId,
    required this.name,
    required this.isVoice,
    this.topic,
    required this.searchOpen,
    required this.onToggleSearch,
  });

  final String channelId;
  final String name;
  final bool isVoice;

  /// Null for no topic; the server never stores a blank one.
  final String? topic;
  final bool searchOpen;
  final VoidCallback onToggleSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final membersVisible = ref.watch(memberPaneVisibleProvider);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(isVoice ? AppIcons.voice : AppIcons.hash,
              size: AppSizes.icon16, color: tokens.textSecondary),
          const SizedBox(width: AppSpacing.s8),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              // The design's 17px header size was deliberately dropped from
              // the six-step type scale (see app_typography.dart): it never
              // differed from body except in weight, so weight alone carries
              // the same hierarchy here.
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.medium,
              ),
            ),
          ),
          if (topic != null && topic!.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.s12),
            Container(
              width: 1,
              height: 20,
              color: tokens.borderSubtle,
            ),
            const SizedBox(width: AppSpacing.s12),
            Flexible(
              flex: 2,
              child: Text(
                topic!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
          ],
          const Spacer(),
          _PinPill(channelId: channelId),
          const SizedBox(width: AppSpacing.s8),
          AppIconButton(
            icon: AppIcons.search,
            semanticLabel: 'Search messages',
            active: searchOpen,
            onPressed: onToggleSearch,
          ),
          AppIconButton(
            icon: AppIcons.members,
            semanticLabel: 'Toggle member list',
            active: membersVisible,
            onPressed: () => ref
                .read(memberPaneVisibleProvider.notifier)
                .state = !membersVisible,
          ),
        ],
      ),
    );
  }
}

/// A real, live count from [pinsControllerProvider]: a dash while the first
/// fetch is in flight, the true count (including zero) once it lands.
/// Tapping opens [showPinnedMessagesSheet], which is the one place pins
/// round-trip a write (unpinning); pinning a message itself has nowhere to
/// live yet, since it would need the shared context menu this client does
/// not build (see the phase 2 known-gaps note in the project's knowledge
/// base) rather than a new, unreviewed affordance on every message row.
class _PinPill extends ConsumerWidget {
  const _PinPill({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final pinned = ref.watch(pinsControllerProvider(channelId));
    final label = pinned == null ? '-' : '${pinned.length}';

    return GestureDetector(
      onTap: () => showPinnedMessagesSheet(context, channelId),
      child: Semantics(
        button: true,
        label: pinned == null
            ? 'Pinned messages, loading'
            : 'Pinned messages, ${pinned.length}',
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
          decoration: BoxDecoration(
            border: Border.all(color: tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.pin, size: 14, color: tokens.textSecondary),
              const SizedBox(width: AppSpacing.s4),
              Text(
                label,
                style: AppText.micro.copyWith(
                  color: tokens.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
