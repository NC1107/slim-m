// SPDX-License-Identifier: Apache-2.0
/// Reporting and blocking, from wherever they are offered.
///
/// One implementation for both subjects. Report and block existed twice before
/// this, once for a member row and once for a message's author, with the same
/// success wording written out in both files and the same catch around a
/// different verb. Two copies of a safety action is two places for the copy to
/// stop matching what actually happens, and the block half had already drifted:
/// it promised messages were hidden while nothing filtered any.
///
/// Every function here takes a [ProviderContainer], not a [WidgetRef]: the
/// caller dismisses the surface these are offered from before the request
/// answers (a popover pops, then a dialog is awaited), and a `WidgetRef` tied
/// to that surface's element throws once it is disposed. A container has no
/// such lifetime, so it is what a caller must capture before dismissing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import '../providers/blocks_controller.dart';
import '../providers/providers.dart';
import 'report_dialog.dart';

void _say(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Files a report about [subjectId], once the reporter has given a reason.
///
/// [subjectLabel] names the thing in the prompt ("this member", "this message"),
/// and is the only difference between the two callers.
Future<void> fileReport(
  BuildContext context,
  ProviderContainer container, {
  required api.ReportSubject subject,
  required String subjectId,
  required String subjectLabel,
}) async {
  final reason = await promptReportReason(context, subjectLabel: subjectLabel);
  if (reason == null || !context.mounted) return;
  try {
    await container
        .read(apiProvider)
        .report(subject: subject, subjectId: subjectId, reason: reason);
    if (!context.mounted) return;
    _say(context, 'Report filed. A moderator will review it.');
  } on api.ApiException catch (e) {
    if (!context.mounted) return;
    _say(context, 'Could not file the report. ${e.message}');
  }
}

/// Blocks [userId]; see `SlimmApi.blockUser` for why they are never told.
///
/// Goes through [blocksProvider] rather than the API directly, so the id lands
/// in the set every read surface filters against and the transcript reacts to
/// the tap. The wording says only what is really covered: messages, reactions
/// and typing go, and the person stays in the member list where the block can
/// be undone.
Future<void> blockUser(
  BuildContext context,
  ProviderContainer container,
  String userId,
) async {
  try {
    await container.read(blocksProvider.notifier).block(userId);
    if (!context.mounted) return;
    _say(context, 'Blocked. You will not see what they post.');
  } on api.ApiException catch (e) {
    if (!context.mounted) return;
    _say(context, 'Could not block that user. ${e.message}');
  }
}

/// Unblocks [userId], reporting a failure rather than swallowing it.
Future<void> unblockUser(
  BuildContext context,
  ProviderContainer container,
  String userId,
) async {
  try {
    await container.read(blocksProvider.notifier).unblock(userId);
    if (!context.mounted) return;
    _say(context, 'Unblocked.');
  } on api.ApiException catch (e) {
    if (!context.mounted) return;
    _say(context, 'Could not unblock that user. ${e.message}');
  }
}
