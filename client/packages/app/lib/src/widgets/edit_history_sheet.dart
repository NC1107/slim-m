// SPDX-License-Identifier: Apache-2.0
/// The sheet the "(edited)" marker opens: every version a message has held,
/// oldest first, ending with its current content, each labelled with when it
/// became the message's text.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/display_preferences.dart';
import '../providers/edit_history_provider.dart';
import 'message_row_identity.dart' show formatMessageDay, formatMessageTime;

/// Sizes the sheet body, so a test measures it directly rather than inferring
/// the layout from a screenshot - the shape `pinnedMessagesBodyBoxKey` uses.
const editHistoryBodyBoxKey = Key('edit_history_body_box');

/// Opens the edit-history sheet for one message.
Future<void> showMessageEditHistorySheet(
  BuildContext context,
  String channelId,
  String messageId,
) {
  return showAppSheet<void>(
    context,
    maxWidth: 560,
    scrolls: true,
    builder: (context) =>
        _EditHistorySheet(channelId: channelId, messageId: messageId),
  );
}

class _EditHistorySheet extends ConsumerWidget {
  const _EditHistorySheet({required this.channelId, required this.messageId});

  final String channelId;
  final String messageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final history = ref.watch(
      messageEditHistoryProvider((channelId: channelId, messageId: messageId)),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            0,
            AppSpacing.s16,
            AppSpacing.s12,
          ),
          child: Row(
            children: [
              Icon(
                AppIcons.activityLog,
                size: AppSizes.icon16,
                color: tokens.textSecondary,
              ),
              const SizedBox(width: AppSpacing.s8),
              Text(
                'Edit history',
                style: AppText.body.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: AppWeights.semi,
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: KeyedSubtree(
            key: editHistoryBodyBoxKey,
            child: AppAsyncView<List<api.MessageRevision>>(
              value: AppAsyncState(
                data: history.valueOrNull,
                // Cleared while loading so a retry (reloaded with the error retained) shows the spinner, not a frozen banner.
                error: history.isLoading ? null : history.error,
              ),
              errorMessage: 'Could not load edit history.',
              onRetry: () => ref.invalidate(
                messageEditHistoryProvider((
                  channelId: channelId,
                  messageId: messageId,
                )),
              ),
              isEmpty: (versions) => versions.isEmpty,
              emptyMessage: 'This message has no recorded history.',
              data: (context, versions) => _Versions(versions: versions),
            ),
          ),
        ),
      ],
    );
  }
}

class _Versions extends ConsumerWidget {
  const _Versions({required this.versions});

  final List<api.MessageRevision> versions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final use24Hour = watchUse24Hour(ref, context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        AppSpacing.s16,
      ),
      shrinkWrap: true,
      itemCount: versions.length,
      separatorBuilder: (_, __) => const Divider(height: AppSpacing.s24),
      itemBuilder: (context, i) => _VersionTile(
        version: versions[i],
        label: _label(i, versions.length),
        use24Hour: use24Hour,
      ),
    );
  }

  static String _label(int index, int count) {
    // Last first, so a single-element list reads as the current content it is, not a lone "Original".
    if (index == count - 1) return 'Current';
    if (index == 0) return 'Original';
    return 'Edited';
  }
}

class _VersionTile extends StatelessWidget {
  const _VersionTile({
    required this.version,
    required this.label,
    required this.use24Hour,
  });

  final api.MessageRevision version;
  final String label;
  final bool use24Hour;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final when =
        '${formatMessageDay(version.at)} at '
        '${formatMessageTime(version.at, use24Hour: use24Hour)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: AppText.micro.copyWith(
                color: tokens.textSecondary,
                fontWeight: AppWeights.semi,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: Text(
                when,
                style: AppText.micro.copyWith(color: tokens.textSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s4),
        SelectableText(
          version.content,
          style: AppText.body.copyWith(color: tokens.textPrimary),
        ),
      ],
    );
  }
}
