// SPDX-License-Identifier: Apache-2.0
/// Lets a reporter check on a report they filed, by pasting back the id
/// `fileReport`'s confirmation toast shows them.
///
/// Before `GET /reports/mine/{reportId}` existed, every report-reading
/// surface sat behind deployment-wide MANAGE_MESSAGES, so filing a report
/// was fire-and-forget: nothing told the person who filed it whether it had
/// reached anyone. This is the client side of that narrow, status-only read
/// - not a queue, not a history, just "is the one report I gave you this id
/// for still open".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import 'settings_section_header.dart';

class ReportStatusSection extends ConsumerStatefulWidget {
  const ReportStatusSection({super.key});

  @override
  ConsumerState<ReportStatusSection> createState() =>
      _ReportStatusSectionState();
}

class _ReportStatusSectionState extends ConsumerState<ReportStatusSection> {
  final _idController = TextEditingController();
  api.MyReportStatus? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final reportId = _idController.text.trim();
    if (reportId.isEmpty) return;
    setState(() {
      _busy = true;
      _result = null;
      _error = null;
    });
    try {
      final status = await ref.read(apiProvider).myReportStatus(reportId);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = status;
      });
    } on api.NotFoundException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // Same wording either way; the server route refuses to tell those apart.
        _error = 'No report found with that ID.';
      });
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not check that report. ${e.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return SettingsSectionCard(
      title: 'Report status',
      description:
          'Paste the ID you were given when you filed a report to see '
          'whether it is still open or has been resolved. This only ever '
          'shows reports you filed yourself.',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppInput(
                controller: _idController,
                placeholder: 'Report ID',
                mono: true,
                size: AppInputSize.sm,
                onSubmitted: (_) => _check(),
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            AppButton(
              label: 'Check',
              size: AppButtonSize.sm,
              disabled: _busy,
              onPressed: _check,
            ),
          ],
        ),
        if (_result case final status?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s12),
            child: Text(
              status.resolved
                  ? 'Resolved. Filed ${_filedAgo(status.createdAt)}.'
                  : 'Still open. Filed ${_filedAgo(status.createdAt)}.',
              style: AppText.body.copyWith(color: tokens.textPrimary),
            ),
          ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s12),
            child: AppErrorState(
              message: error,
              onDismiss: () => setState(() => _error = null),
            ),
          ),
      ],
    );
  }
}

/// A short, relative "filed X ago" for [createdAtMs] (Unix milliseconds).
/// Matches the granularity `canvas_activity_panel.dart`'s own relative
/// timestamp already uses, extended with weeks: a filed report is realistic
/// to check back on well after a day has passed, where a canvas activity
/// entry is not.
String _filedAgo(int createdAtMs) {
  final at = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  final elapsed = DateTime.now().difference(at);
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
  return '${elapsed.inDays ~/ 7}w ago';
}
