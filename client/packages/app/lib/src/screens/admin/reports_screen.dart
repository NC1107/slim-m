// SPDX-License-Identifier: Apache-2.0
/// The moderation queue: `GET /reports` and `PATCH /reports/{id}`. Requires
/// MANAGE_MESSAGES, which is why the settings row that reaches this is
/// itself gated on that bit; a caller without it never sees the link, and
/// the server refuses the request either way if one arrives regardless.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/reports_controller.dart';
import '../../routing/routes.dart';
import '../settings_screen_scaffold.dart';
import 'report_card.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(reportsControllerProvider);
    final controller = ref.read(reportsControllerProvider.notifier);
    return SettingsScreenScaffold(
      title: 'Reports',
      backTooltip: 'Back to Space settings',
      backFallback: Routes.spaceSettings,
      scrollable: false,
      padding: EdgeInsets.zero,
      child: AppAsyncView<List<api.Report>>(
        // Only when there is nothing to show instead; see _LoadMoreRow.
        value: AppAsyncState(
          data: reports.loading && reports.reports.isEmpty
              ? null
              : reports.reports,
          error: reports.reports.isEmpty ? reports.error : null,
        ),
        errorMessage: 'Could not load reports.',
        onRetry: controller.refresh,
        isEmpty: (list) => list.isEmpty,
        emptyMessage: 'The queue is empty.',
        data: (context, list) => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.s16),
          // One trailing row when the last page came back full; see the controller.
          itemCount: reports.more || reports.error != null
              ? list.length + 1
              : list.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
          itemBuilder: (context, i) => i == list.length
              ? _LoadMoreRow(
                  loading: reports.loading,
                  error: reports.error,
                  onTap: controller.loadMore,
                )
              // Keyed by id, or a shortened page hands the next report the previous card's busy state.
              : ReportCard(key: ValueKey(list[i].id), report: list[i]),
        ),
      ),
    );
  }
}

/// The end of a full page: more reports may follow, and only asking finds out.
///
/// Carries the failure of the last attempt too, inline and next to its retry,
/// rather than letting it replace the pages already on screen.
class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({
    required this.loading,
    required this.error,
    required this.onTap,
  });

  final bool loading;
  final String? error;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.s8),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (error case final message?) {
      return AppErrorState(
        message: 'Could not load more reports.',
        detail: message,
        onRetry: () => unawaited(onTap()),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: AppButton(
          label: 'Load more',
          variant: AppButtonVariant.secondary,
          onPressed: () => unawaited(onTap()),
        ),
      ),
    );
  }
}
