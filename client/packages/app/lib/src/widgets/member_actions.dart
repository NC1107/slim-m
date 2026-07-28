// SPDX-License-Identifier: Apache-2.0
/// Acting on one member, from the row's own context menu.
///
/// Split out of `member_pane.dart`, for the same reason
/// `channel_message_actions.dart` was split out of `channel_screen.dart`:
/// both need a [BuildContext] to put a snackbar in front of somebody, which
/// is not something the pure roster/presence layer in
/// `providers/member_presence.dart` needs at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import '../providers/providers.dart';
import 'report_dialog.dart';

/// Files a report against a member, from the row's context menu.
Future<void> reportMember(
  BuildContext context,
  WidgetRef ref,
  api.UserProfile profile,
) async {
  final reason = await promptReportReason(context, subjectLabel: 'this member');
  if (reason == null || !context.mounted) return;
  try {
    await ref
        .read(apiProvider)
        .report(
          subject: api.ReportSubject.user,
          subjectId: profile.id,
          reason: reason,
        );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report filed. A moderator will review it.'),
      ),
    );
  } on api.ApiException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not file the report. ${e.message}')),
    );
  }
}

/// Blocks a member from the row's context menu; see `SlimmApi.blockUser`
/// for why the blocked member is never told.
Future<void> blockMember(
  BuildContext context,
  WidgetRef ref,
  api.UserProfile profile,
) async {
  try {
    await ref.read(apiProvider).blockUser(profile.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Blocked. Their messages are hidden for you.'),
      ),
    );
  } on api.ApiException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not block that user. ${e.message}')),
    );
  }
}
