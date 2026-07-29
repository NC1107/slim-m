// SPDX-License-Identifier: Apache-2.0
/// The moderation queue: `GET /reports` and `PATCH /reports/{id}`. Requires
/// MANAGE_MESSAGES, which is why the settings row that reaches this is
/// itself gated on that bit; a caller without it never sees the link, and
/// the server refuses the request either way if one arrives regardless.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../format.dart';
import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../../routing/close_screen.dart';
import '../../widgets/confirm_dialog.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(openReportsProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        leading: BackToButton(
          tooltip: 'Back to Space settings',
          fallback: Routes.spaceSettings,
        ),
      ),
      // top: false because the AppBar already clears the status bar.
      body: AppContentColumn(
        child: SafeArea(
          top: false,
          child: reports.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                'Could not load reports.',
                style: TextStyle(color: tokens.textSecondary),
              ),
            ),
            data: (list) => list.isEmpty
                ? Center(
                    child: Text(
                      'The queue is empty.',
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.s16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.s12),
                    itemBuilder: (context, i) => _ReportCard(report: list[i]),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends ConsumerStatefulWidget {
  const _ReportCard({required this.report});

  final api.Report report;

  @override
  ConsumerState<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<_ReportCard> {
  bool _busy = false;

  Future<void> _resolve(api.ReportResolution resolution) async {
    final verb = resolution == api.ReportResolution.resolved
        ? 'Resolve'
        : 'Dismiss';
    final confirmed = await confirmDangerousAction(
      context,
      title: '$verb this report?',
      message: resolution == api.ReportResolution.resolved
          ? 'This marks it handled and removes it from the queue. It cannot '
                'be reopened from here.'
          : 'This closes it with no action taken and removes it from the '
                'queue. It cannot be reopened from here.',
      confirmLabel: verb,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .resolveReport(reportId: widget.report.id, resolution: resolution);
      if (context.mounted) ref.invalidate(openReportsProvider);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not close the report. ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final report = widget.report;

    return AppCard(
      title: report.subjectKind == api.ReportSubject.message
          ? 'Reported message'
          : 'Reported user',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(report.reason, style: TextStyle(color: tokens.textPrimary)),
          if (report.snapshot != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Container(
              padding: const EdgeInsets.all(AppSpacing.s8),
              decoration: BoxDecoration(
                color: tokens.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: Text(
                report.snapshot!,
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Filed ${formatDateTime(report.createdAt)}',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                label: 'Dismiss',
                icon: AppIcons.dismiss,
                disabled: _busy,
                onPressed: () => _resolve(api.ReportResolution.dismissed),
              ),
              const SizedBox(width: AppSpacing.s8),
              AppButton(
                label: 'Resolve',
                icon: AppIcons.check,
                variant: AppButtonVariant.primary,
                disabled: _busy,
                onPressed: () => _resolve(api.ReportResolution.resolved),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
