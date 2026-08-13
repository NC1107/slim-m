// SPDX-License-Identifier: Apache-2.0
/// Space usage analytics: `GET`/`PATCH /space/analytics`. Requires
/// MANAGE_SERVER, the same bit `/space/settings` and the Emoji screen use.
///
/// Off by default on every deployment; see
/// `docs/decisions/0008-space-analytics.md`. The toggle at the top is not
/// decoration - it is the whole feature's on switch, and nothing below it is
/// computed while it reads off, including the counts this file derives on
/// read rather than records: the point is that the feature does not run at
/// all until asked for, not only that a background job is paused.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../../widgets/attachment_view.dart' show formatByteSize;
import '../../widgets/run_guarded.dart';
import '../../widgets/settings_section_header.dart';
import '../../widgets/settings_toggle_row.dart';
import '../../widgets/success_flash.dart';
import '../settings_screen_scaffold.dart';
import 'analytics_charts.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) => const SettingsScreenScaffold(
    title: 'Analytics',
    backTooltip: 'Back to Space settings',
    backFallback: Routes.spaceSettings,
    child: AnalyticsPane(),
  );
}

/// The toggle and stats themselves, embeddable as a Space settings pane as
/// well as routed.
class AnalyticsPane extends ConsumerStatefulWidget {
  const AnalyticsPane({super.key});

  @override
  ConsumerState<AnalyticsPane> createState() => _AnalyticsPaneState();
}

class _AnalyticsPaneState extends ConsumerState<AnalyticsPane>
    with GuardedActionState<AnalyticsPane> {
  bool _toggling = false;

  /// The value the toggle shows the instant it is tapped, ahead of the
  /// server's answer: flipped optimistically, reverted on failure, and
  /// retired once the provider delivers a fresh answer of its own.
  bool? _optimistic;

  Future<void> _setEnabled(bool value) async {
    setState(() {
      _toggling = true;
      _optimistic = value;
    });
    final ok = await guard(
      whatFailed: value ? 'turn analytics on' : 'turn analytics off',
      action: () => ref.read(apiProvider).setSpaceAnalyticsEnabled(value),
    );
    if (!mounted) return;
    setState(() {
      _toggling = false;
      if (!ok) _optimistic = null;
    });
    if (ok) ref.invalidate(spaceAnalyticsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(spaceAnalyticsProvider);
    // Once a fresh fetch lands, the server's own answer takes back over.
    ref.listen(spaceAnalyticsProvider, (previous, next) {
      if (next.hasValue && !next.isLoading && _optimistic != null) {
        setState(() => _optimistic = null);
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ToggleCard(
          enabled: _optimistic ?? analytics.valueOrNull?.enabled ?? false,
          busy: _toggling || analytics.isLoading,
          onChanged: _setEnabled,
        ),
        SuccessFlash(tick: successTick),
        if (actionError != null) ...[
          const SizedBox(height: AppSpacing.s8),
          AppErrorState(message: actionError!, onDismiss: clearActionError),
        ],
        const SizedBox(height: AppSpacing.s16),
        AppAsyncView<api.SpaceAnalytics>(
          // A failed retry keeps the stats on screen; see AppAsyncView's own doc.
          value: AppAsyncState(
            data: analytics.valueOrNull,
            error: analytics.error,
          ),
          center: false,
          errorMessage: 'Could not load analytics.',
          onRetry: () => ref.invalidate(spaceAnalyticsProvider),
          data: (context, value) => value.stats == null
              ? const _OffNotice()
              : _StatsView(
                  stats: value.stats!,
                  memberStorage: value.memberStorage ?? const [],
                ),
        ),
        const SizedBox(height: AppSpacing.s16),
        const _RetentionSection(),
      ],
    );
  }
}

class _ToggleCard extends StatelessWidget {
  const _ToggleCard({
    required this.enabled,
    required this.busy,
    required this.onChanged,
  });

  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingsSectionCard(
    children: [
      SettingsToggleRow(
        label: 'Record Space analytics',
        description:
            'Off by default. Counts messages and reads this server\'s '
            'own memory use; never a per-member activity log. Turning '
            'this off hides the numbers below but keeps whatever was '
            'already recorded.',
        value: enabled,
        onChanged: busy ? null : onChanged,
        semanticLabel: enabled ? 'Space analytics on' : 'Space analytics off',
      ),
    ],
  );
}

class _OffNotice extends StatelessWidget {
  const _OffNotice();

  @override
  Widget build(BuildContext context) => const AppCallout(
    tone: AppCalloutTone.info,
    child: Text(
      'Analytics is off. Turn it on above to see message counts, active '
      'hours, and this server\'s own memory use over time.',
    ),
  );
}

class _StatsView extends StatelessWidget {
  const _StatsView({required this.stats, required this.memberStorage});

  final api.AnalyticsStats stats;
  final List<api.MemberAttachmentUsage> memberStorage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _StatTiles(stats: stats),
      const SizedBox(height: AppSpacing.s16),
      MessagesByDayCard(stats: stats),
      const SizedBox(height: AppSpacing.s16),
      ActiveHoursCard(stats: stats),
      const SizedBox(height: AppSpacing.s16),
      MemoryCard(stats: stats),
      const SizedBox(height: AppSpacing.s16),
      MemberStorageCard(usage: memberStorage),
    ],
  );
}

class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.stats});

  final api.AnalyticsStats stats;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.s12,
    runSpacing: AppSpacing.s12,
    children: [
      _StatTile(label: 'Total messages', value: '${stats.totalMessages}'),
      _StatTile(label: 'Members', value: '${stats.memberCount}'),
      _StatTile(label: 'Channels', value: '${stats.channelCount}'),
      _StatTile(
        label: 'Attachments stored',
        value: formatByteSize(stats.attachmentBytes),
      ),
    ],
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return SizedBox(
      width: 150,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: AppText.heading.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              label,
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Days a pruned message is kept before the sweep removes it; index-matched
/// to the segmented options below. `0` is keep forever, the default and
/// what every deployment keeps until an admin sets one.
const _retentionDayOptions = <(String, int)>[
  ('Never', 0),
  ('30 days', 30),
  ('90 days', 90),
  ('365 days', 365),
];

/// The message retention window: an operator disk-pressure control,
/// independent of the analytics toggle above - it stays visible and usable
/// whether or not Space analytics recording is on.
class _RetentionSection extends ConsumerStatefulWidget {
  const _RetentionSection();

  @override
  ConsumerState<_RetentionSection> createState() => _RetentionSectionState();
}

class _RetentionSectionState extends ConsumerState<_RetentionSection>
    with GuardedActionState<_RetentionSection> {
  bool _saving = false;
  int? _optimisticDays;

  Future<void> _setDays(int days) async {
    setState(() {
      _saving = true;
      _optimisticDays = days;
    });
    final ok = await guard(
      whatFailed: 'change the message retention window',
      action: () => ref.read(apiProvider).setSpaceMessageRetentionDays(days),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) _optimisticDays = null;
    });
    if (ok) ref.invalidate(spaceRetentionProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final retention = ref.watch(spaceRetentionProvider);
    ref.listen(spaceRetentionProvider, (previous, next) {
      if (next.hasValue && !next.isLoading && _optimisticDays != null) {
        setState(() => _optimisticDays = null);
      }
    });
    final current = _optimisticDays ?? retention.valueOrNull ?? 0;
    final selectedIndex = _retentionDayOptions.indexWhere(
      (o) => o.$2 == current,
    );

    return SettingsSectionCard(
      title: 'Message retention',
      children: [
        Text(
          'How long a message is kept before it is pruned. Off by default: '
          'nothing is ever deleted unless a window is set here.',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        AppSegmentedControl.inline(
          semanticLabel: 'Message retention window',
          options: [
            for (final option in _retentionDayOptions)
              AppSegmentedOption(label: option.$1, disabled: _saving),
          ],
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onSegmentSelected: (i) => _setDays(_retentionDayOptions[i].$2),
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
