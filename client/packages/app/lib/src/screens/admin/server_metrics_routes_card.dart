// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The route latency table on [ServerMetricsPane]. Split out of
/// `server_metrics_screen.dart` to keep that file to the system and
/// request-volume cards.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../widgets/settings_section_header.dart';

/// Every observed route, slowest p95 first - the order that puts a
/// bottleneck at the top rather than making an admin scan for it.
class SlowestRoutesCard extends StatelessWidget {
  const SlowestRoutesCard({super.key, required this.routes});

  final List<api.RouteMetric> routes;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    if (routes.isEmpty) {
      return SettingsSectionCard(
        title: 'Slowest routes',
        children: [
          Text(
            'No requests recorded since this server process started.',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      );
    }
    final sorted = [...routes]..sort(_byP95Descending);
    return SettingsSectionCard(
      title: 'Slowest routes',
      children: [
        Text(
          'By p95 latency, an estimate over each route\'s own histogram. '
          '${routes.length} route${routes.length == 1 ? '' : 's'} observed.',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        _HeaderRow(),
        for (final route in sorted) _RouteRow(route: route),
      ],
    );
  }
}

/// Unobserved routes sort last rather than first: a route with no p95 has
/// not been called, not answered instantly.
int _byP95Descending(api.RouteMetric a, api.RouteMetric b) {
  final aP95 = a.p95Seconds;
  final bP95 = b.p95Seconds;
  if (aP95 == null && bP95 == null) return 0;
  if (aP95 == null) return 1;
  if (bP95 == null) return -1;
  return bP95.compareTo(aP95);
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final style = AppText.caption.copyWith(color: tokens.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('Route', style: style)),
          Expanded(flex: 1, child: Text('Requests', style: style)),
          Expanded(flex: 1, child: Text('Avg', style: style)),
          Expanded(flex: 1, child: Text('p95', style: style)),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.route});

  final api.RouteMetric route;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final bodyStyle = AppText.body.copyWith(color: tokens.textPrimary);
    final captionStyle = AppText.caption.copyWith(color: tokens.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              '${route.method} ${route.route}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: bodyStyle,
            ),
          ),
          Expanded(flex: 1, child: Text('${route.count}', style: captionStyle)),
          Expanded(
            flex: 1,
            child: Text(formatLatency(route.avgSeconds), style: captionStyle),
          ),
          Expanded(
            flex: 1,
            child: Text(
              route.p95Seconds == null ? '-' : formatLatency(route.p95Seconds!),
              style: captionStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// "3 ms", "42 ms", "1.2 s" - the two units a request latency ever falls
/// into on this server, given the 30-second request timeout as a ceiling.
String formatLatency(double seconds) {
  final ms = seconds * 1000;
  if (ms < 1000) return '${ms.round()} ms';
  return '${(ms / 1000).toStringAsFixed(1)} s';
}
