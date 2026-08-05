// SPDX-License-Identifier: Apache-2.0
/// The three chart cards on [AnalyticsScreen]: messages by day, active
/// hours, and this server's own memory. Split out of `analytics_screen.dart`
/// to keep that file under the review budget.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../widgets/analytics_bar_chart.dart';
import '../../widgets/attachment_view.dart' show formatByteSize;

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

    return AppCard(
      title: 'Messages, last 30 days',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
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

    return AppCard(
      title: 'Active hours, last 30 days (UTC)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
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
      return AppCard(
        title: 'Server memory use',
        child: Text(
          'Not enough data yet. A reading is taken each time this screen '
          'loads, at most once every five minutes, so check back shortly.',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
      );
    }
    final latest = samples.last.rssBytes;
    final peak = samples.map((s) => s.rssBytes).reduce((a, b) => a > b ? a : b);
    final summaryLabel = samples
        .map((s) => formatByteSize(s.rssBytes))
        .join(', ');

    return AppCard(
      title: 'Server memory use',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnalyticsBarChart(
            values: samples.map((s) => s.rssBytes.toDouble()).toList(),
            semanticsLabel:
                'Server memory readings, oldest first: $summaryLabel',
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Latest: ${formatByteSize(latest)} · peak: ${formatByteSize(peak)}',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}
