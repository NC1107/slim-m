// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Controls a bot puts in a call, shown in the call's dock only while that bot
/// is on the call. See docs/decisions/0045-bot-contributed-ui.md.
///
/// Layout follows width, never platform (docs/design/desktop-vs-mobile.md,
/// law 2): the buttons are the design system's own and grow to the touch
/// floor by themselves, and the row wraps rather than scrolling, so a phone
/// gets more lines instead of a hidden control. Below [kCompactWidth] a bot
/// is one row: its name as a small label, then an icon chip per control, the
/// same chip the call's own controls use, labelled by tooltip and semantics.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/bot_ui_uses.dart';
import '../screens/call_dock_button.dart';

/// One bot's controls for the call.
class BotCallGroup {
  const BotCallGroup({required this.bot, required this.controls});

  final api.ChannelBotUi bot;
  final List<api.BotUiEntry> controls;
}

/// The bots that both registered controls and are on the call, so a bot that
/// has left leaves nothing behind. [participantIds] are the call's user ids.
List<BotCallGroup> botCallGroups(
  List<api.ChannelBotUi> bots,
  Set<String> participantIds,
) => [
  for (final bot in bots)
    if (bot.callControls.isNotEmpty && participantIds.contains(bot.botUserId))
      BotCallGroup(bot: bot, controls: bot.callControls),
];

/// Widest a bot's name grows beside its chips before it ellipsizes.
const double _compactNameMaxWidth = 88;

/// Widest the strip grows, so a wide window keeps it a control and not a bar.
const double _maxWidth = 480;

IconData _iconFor(String? name) => switch (name) {
  'play' => AppIcons.play,
  'pause' => AppIcons.pause,
  'stop' => AppIcons.callStop,
  'skip_next' => AppIcons.callSkipNext,
  'skip_previous' => AppIcons.callSkipPrevious,
  'volume' => AppIcons.speaker,
  'volume_off' => AppIcons.speakerOff,
  'repeat' => AppIcons.callRepeat,
  'shuffle' => AppIcons.callShuffle,
  'list' => AppIcons.callList,
  _ => AppIcons.callControl,
};

class BotCallControls extends ConsumerWidget {
  const BotCallControls({
    super.key,
    required this.channelId,
    required this.groups,
  });

  final String channelId;
  final List<BotCallGroup> groups;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (groups.isEmpty) return const SizedBox.shrink();
    final uses = ref.watch(botUiUsesProvider);
    final controller = ref.read(botUiUsesProvider.notifier);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in groups)
            _Group(
              group: group,
              uses: {
                for (final control in group.controls)
                  control.id:
                      uses[controlUseKey(
                        channelId,
                        group.bot.botUserId,
                        control.id,
                      )],
              },
              onUse: (control) => unawaited(
                controller.useCallControl(
                  channelId: channelId,
                  botId: group.bot.botUserId,
                  entryId: control.id,
                ),
              ),
              onDismiss: (control) => controller.dismiss(
                controlUseKey(channelId, group.bot.botUserId, control.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.uses,
    required this.onUse,
    required this.onDismiss,
  });

  final BotCallGroup group;
  final Map<String, BotUiUse?> uses;
  final ValueChanged<api.BotUiEntry> onUse;
  final ValueChanged<api.BotUiEntry> onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final failed = group.controls
        .where((c) => uses[c.id]?.failure != null)
        .firstOrNull;
    final compact = MediaQuery.sizeOf(context).width < kCompactWidth;
    final name = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            group.bot.botDisplayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        const AppBadge(variant: AppBadgeVariant.tag, label: 'Bot'),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            _CompactRow(
              name: name,
              controls: group.controls,
              uses: uses,
              onUse: onUse,
            )
          else ...[
            name,
            const SizedBox(height: AppSpacing.s4),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                for (final control in group.controls)
                  _ControlButton(
                    control: control,
                    pending: uses[control.id]?.pending ?? false,
                    onPressed: () => onUse(control),
                  ),
              ],
            ),
          ],
          if (failed != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: AppErrorState(
                message: uses[failed.id]!.failure!,
                onRetry: () {
                  onDismiss(failed);
                  unawaited(uses[failed.id]!.retry());
                },
                onDismiss: () => onDismiss(failed),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactRow extends StatelessWidget {
  const _CompactRow({
    required this.name,
    required this.controls,
    required this.uses,
    required this.onUse,
  });

  final Widget name;
  final List<api.BotUiEntry> controls;
  final Map<String, BotUiUse?> uses;
  final ValueChanged<api.BotUiEntry> onUse;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _compactNameMaxWidth),
        child: name,
      ),
      const SizedBox(width: AppSpacing.s8),
      Expanded(
        child: Wrap(
          alignment: WrapAlignment.end,
          runAlignment: WrapAlignment.end,
          children: [
            for (final control in controls)
              CallDockButton(
                icon: _iconFor(control.icon),
                tooltip: control.label,
                active: false,
                pending: uses[control.id]?.pending ?? false,
                onPressed: () => onUse(control),
              ),
          ],
        ),
      ),
    ],
  );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.control,
    required this.pending,
    required this.onPressed,
  });

  final api.BotUiEntry control;
  final bool pending;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    AppButton build({required bool busy}) => AppButton(
      label: control.label,
      variant: AppButtonVariant.secondary,
      icon: _iconFor(control.icon),
      busy: busy,
      onPressed: onPressed,
    );
    if (!pending) return build(busy: false);
    // The invisible copy holds the label's width so the spinner swaps in without a reflow.
    return Stack(
      children: [
        Visibility(
          visible: false,
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          child: build(busy: false),
        ),
        Positioned.fill(child: build(busy: true)),
      ],
    );
  }
}
