// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Channel settings' slow-mode section: `PATCH /channels/{id}`
/// ([api.SlimmApiChannelAdmin.updateChannel]), the same route
/// `ChannelGeneralSection` saves name and topic through. Split into its own
/// section rather than folded into that one, the same way the danger zone is
/// its own file: one concern per section card. Saves on tap rather than
/// behind a separate Save button, the same optimistic-set shape
/// `_RetentionSection` (`admin/performance_screen.dart`) uses for its own
/// "off plus a few presets" control.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Unaliased for the `updateChannel` extension method; `Channel` hidden since `slimm_data`'s own (this section's `channel` field type) would otherwise collide.
import 'package:slimm_api/api.dart' hide Channel;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../widgets/run_guarded.dart';
import '../widgets/settings_section_header.dart';
import '../widgets/success_flash.dart';

/// The interval choices offered here, index-matched to the segmented
/// control below. Not the server's own full 0..21600 range
/// (`SLOW_MODE_MAX_SECONDS` in `channel_slow_mode.rs`) - a curated set of
/// common intervals, the same shape `_retentionDayOptions` uses for message
/// retention.
const List<(String, int)> slowModeOptions = [
  ('Off', 0),
  ('10s', 10),
  ('30s', 30),
  ('1m', 60),
  ('10m', 600),
];

class ChannelSlowModeSection extends ConsumerStatefulWidget {
  const ChannelSlowModeSection({super.key, required this.channel});

  final Channel channel;

  @override
  ConsumerState<ChannelSlowModeSection> createState() =>
      _ChannelSlowModeSectionState();
}

class _ChannelSlowModeSectionState extends ConsumerState<ChannelSlowModeSection>
    with GuardedActionState<ChannelSlowModeSection> {
  bool _saving = false;
  int? _optimisticSeconds;

  Future<void> _setSeconds(int seconds) async {
    setState(() {
      _saving = true;
      _optimisticSeconds = seconds;
    });
    final ok = await guard(
      whatFailed: 'change slow mode',
      action: () async {
        final updated = await ref
            .read(apiProvider)
            .updateChannel(
              channelId: widget.channel.id,
              slowModeSeconds: seconds,
            );
        final store = await ref.read(storeProvider.future);
        await store.upsertChannels([updated]);
      },
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) _optimisticSeconds = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final current = _optimisticSeconds ?? widget.channel.slowModeSeconds;
    final selectedIndex = slowModeOptions.indexWhere((o) => o.$2 == current);

    return SettingsSectionCard(
      title: 'Slow mode',
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'How long a member must wait between their own messages here. '
          'Off by default. A member who can manage this channel is never '
          'slow-moded.',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        AppSegmentedControl.inline(
          semanticLabel: 'Slow mode interval',
          options: [
            for (final option in slowModeOptions)
              AppSegmentedOption(label: option.$1, disabled: _saving),
          ],
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onSegmentSelected: (i) => _setSeconds(slowModeOptions[i].$2),
        ),
        SuccessFlash(tick: successTick),
        if (actionError != null) ...[
          const SizedBox(height: AppSpacing.s8),
          AppErrorState(message: actionError!, onDismiss: clearActionError),
        ],
      ],
    );
  }
}
