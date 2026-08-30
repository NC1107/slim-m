// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The three chart cards on [AnalyticsScreen]: messages by day, active
/// hours, and this server's own memory. Split out of `analytics_screen.dart`
/// to keep that file under the review budget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/user_profiles.dart';
import '../../widgets/analytics_bar_chart.dart';
import '../../widgets/attachment_view.dart' show formatByteSize;
import '../../widgets/author_label.dart';
import '../../widgets/settings_section_header.dart';

class MessagesByDayCard extends StatelessWidget {
  const MessagesByDayCard({super.key, required this.stats});

  final api.AnalyticsStats stats;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final days = stats.messagesByDay;
    final total = days.fold<int>(0, (sum, d) => sum + d.count);
    final busiest = days.isEmpty
        ? null
        : days.reduce((a, b) => b.count > a.count ? b : a);
    final summaryLabel = days.map((d) => '${d.date}: ${d.count}').join(', ');

    return SettingsSectionCard(
      title: 'Messages, last 30 days',
      children: [
        AnalyticsBarChart(
          values: days.map((d) => d.count.toDouble()).toList(),
          semanticsLabel: 'Messages per day: $summaryLabel',
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          busiest == null || busiest.count == 0
              ? 'Total: $total'
              : 'Total: $total · busiest day: ${busiest.date} '
                    '(${busiest.count})',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }
}

class ActiveHoursCard extends StatelessWidget {
  const ActiveHoursCard({super.key, required this.stats});

  final api.AnalyticsStats stats;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final hours = stats.activeHours;
    final total = hours.fold<int>(0, (sum, c) => sum + c);
    var peakHour = 0;
    for (var i = 1; i < hours.length; i++) {
      if (hours[i] > hours[peakHour]) peakHour = i;
    }
    final summaryLabel = [
      for (var i = 0; i < hours.length; i++)
        '${i.toString().padLeft(2, '0')}:00 UTC: ${hours[i]}',
    ].join(', ');

    return SettingsSectionCard(
      title: 'Active hours, last 30 days (UTC)',
      children: [
        AnalyticsBarChart(
          values: hours.map((c) => c.toDouble()).toList(),
          semanticsLabel: 'Messages per UTC hour of day: $summaryLabel',
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          total == 0
              ? 'No messages in this window.'
              : 'Busiest hour: ${peakHour.toString().padLeft(2, '0')}:00 '
                    'UTC (${hours[peakHour]} messages), summed across '
                    'every member.',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }
}

class MemoryCard extends StatelessWidget {
  const MemoryCard({super.key, required this.stats});

  final api.AnalyticsStats stats;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final samples = stats.memorySamples;
    if (samples.isEmpty) {
      return SettingsSectionCard(
        title: 'Server memory use',
        children: [
          Text(
            'Not enough data yet. A reading is taken each time this screen '
            'loads, at most once every five minutes, so check back shortly.',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      );
    }
    final latest = samples.last.rssBytes;
    final peak = samples.map((s) => s.rssBytes).reduce((a, b) => a > b ? a : b);
    final summaryLabel = samples
        .map((s) => formatByteSize(s.rssBytes))
        .join(', ');

    return SettingsSectionCard(
      title: 'Server memory use',
      children: [
        AnalyticsBarChart(
          values: samples.map((s) => s.rssBytes.toDouble()).toList(),
          semanticsLabel: 'Server memory readings, oldest first: $summaryLabel',
        ),
        const SizedBox(height: AppSpacing.s8),
        Text(
          'Latest: ${formatByteSize(latest)} · peak: ${formatByteSize(peak)}',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }
}

/// Attachment bytes per member, heaviest first - never part of [_StatTiles]
/// or the aggregate charts above: `member_storage` is the one place this
/// screen names a member, for storage stewardship rather than usage
/// surveillance. See `docs/decisions/0008-space-analytics.md`.
class MemberStorageCard extends ConsumerWidget {
  const MemberStorageCard({super.key, required this.usage});

  final List<api.MemberAttachmentUsage> usage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    resolveAuthorProfiles(ref, usage.map((u) => u.userId));
    final profiles = ref.watch(batchProfilesControllerProvider);

    if (usage.isEmpty) {
      return SettingsSectionCard(
        title: 'Attachment storage by member',
        children: [
          Text(
            'Nobody has uploaded an attachment yet.',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      );
    }

    return SettingsSectionCard(
      title: 'Attachment storage by member',
      children: [
        for (final member in usage)
          _MemberStorageRow(usage: member, profiles: profiles),
      ],
    );
  }
}

class _MemberStorageRow extends StatelessWidget {
  const _MemberStorageRow({required this.usage, required this.profiles});

  final api.MemberAttachmentUsage usage;
  final Map<String, api.UserProfile?> profiles;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final name = authorLabel(
      authorId: usage.userId,
      cachedDisplayName: null,
      profiles: profiles,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(color: tokens.textPrimary),
            ),
          ),
          Text(
            formatByteSize(usage.attachmentBytes),
            style: AppText.body.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
