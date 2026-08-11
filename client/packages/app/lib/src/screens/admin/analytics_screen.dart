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
import '../settings_screen_scaffold.dart';
import 'analytics_charts.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with GuardedActionState<AnalyticsScreen> {
  bool _toggling = false;

  Future<void> _setEnabled(bool value) async {
    setState(() => _toggling = true);
    final ok = await guard(
      whatFailed: value ? 'turn analytics on' : 'turn analytics off',
      action: () => ref.read(apiProvider).setSpaceAnalyticsEnabled(value),
    );
    if (!mounted) return;
    setState(() => _toggling = false);
    if (ok) ref.invalidate(spaceAnalyticsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(spaceAnalyticsProvider);

    return SettingsScreenScaffold(
      title: 'Analytics',
      backTooltip: 'Back to Space settings',
      backFallback: Routes.spaceSettings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ToggleCard(
            enabled: analytics.valueOrNull?.enabled ?? false,
            busy: _toggling || analytics.isLoading,
            onChanged: _setEnabled,
          ),
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
                : _StatsView(stats: value.stats!),
          ),
        ],
      ),
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
  const _StatsView({required this.stats});

  final api.AnalyticsStats stats;

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
