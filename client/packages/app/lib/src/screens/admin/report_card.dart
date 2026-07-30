// SPDX-License-Identifier: Apache-2.0
/// One report in the moderation queue, split out of `reports_screen.dart` to
/// keep that file under budget.
///
/// A report is an irreversible-close decision, and the card has to name what
/// is being decided: who filed it, and for a user report, who is being
/// reported. Both resolve through [batchProfilesControllerProvider] rather
/// than rendering the raw id the wire carries.
///
/// A message report needs its author named too, and `subject_id` is the
/// *message's* id rather than the author's - so that one could not be resolved
/// from what the wire carried. `Report.subjectAuthorId` was added for this,
/// joined at read time server-side, and it is null in the three cases an
/// author id is always null: a user report, a message since hard-deleted, and
/// an anonymized account.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../format.dart';
import '../../providers/providers.dart';
import '../../providers/reports_controller.dart';
import '../../providers/user_profiles.dart';
import '../../widgets/confirm_dialog.dart';

class ReportCard extends ConsumerStatefulWidget {
  const ReportCard({super.key, required this.report});

  final api.Report report;

  @override
  ConsumerState<ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends ConsumerState<ReportCard> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _requestProfiles();
  }

  @override
  void didUpdateWidget(covariant ReportCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.id != widget.report.id) _requestProfiles();
  }

  /// The ids this card needs a name for: the reporter always, and the
  /// subject too when the report is about a user rather than a message.
  void _requestProfiles() {
    final report = widget.report;
    final ids = <String>{
      if (report.reporterId != null) report.reporterId!,
      if (report.subjectKind == api.ReportSubject.user) report.subjectId,
      if (report.subjectAuthorId != null) report.subjectAuthorId!,
    };
    if (ids.isEmpty) return;
    unawaited(ref.read(batchProfilesControllerProvider.notifier).resolve(ids));
  }

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
      if (context.mounted) {
        await ref.read(reportsControllerProvider.notifier).refresh();
      }
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
    final profiles = ref.watch(batchProfilesControllerProvider);
    final reporterLabel = _reporterLabel(report.reporterId, profiles);

    return AppCard(
      title: report.subjectKind == api.ReportSubject.message
          ? 'Reported message'
          : 'Reported user',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.subjectKind == api.ReportSubject.message) ...[
            Text(
              _authorHeadline(report.subjectAuthorId, profiles),
              style: AppText.body.copyWith(
                fontWeight: AppWeights.semi,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          if (report.subjectKind == api.ReportSubject.user) ...[
            Text(
              _subjectHeadline(report.subjectId, profiles),
              style: AppText.body.copyWith(
                fontWeight: AppWeights.semi,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
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
                // Bounded so one long paste cannot grow past the rest.
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Filed by $reporterLabel · ${formatDateTime(report.createdAt)}',
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

/// The reporter's name for the "Filed by ..." line. [id] itself null (the
/// server already anonymized that account) and a batch fetch that came back
/// without it (deleted since) read the same honest way; an id not yet asked
/// for reads as still loading.
String _reporterLabel(String? id, Map<String, api.UserProfile?> profiles) {
  if (id == null) return 'a deleted account';
  if (!profiles.containsKey(id)) return 'someone';
  return profiles[id]?.displayName ?? 'a deleted account';
}

/// The reported user's name for a user report's headline: the same three
/// states as [_reporterLabel], worded to stand alone rather than complete a
/// sentence.
String _subjectHeadline(String id, Map<String, api.UserProfile?> profiles) {
  if (!profiles.containsKey(id)) return 'Resolving...';
  return profiles[id]?.displayName ?? 'Deleted account';
}

/// Who wrote the reported message, for the headline of a message report.
///
/// A null id is not a lookup that failed: the server sends none when the
/// message has been hard-deleted or its author anonymized, and saying so is
/// more use to a moderator than a name that would be wrong.
String _authorHeadline(String? id, Map<String, api.UserProfile?> profiles) {
  if (id == null) return 'Author no longer on this Space';
  if (!profiles.containsKey(id)) return 'Resolving...';
  return profiles[id]?.displayName ?? 'Deleted account';
}
