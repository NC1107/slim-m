// SPDX-License-Identifier: Apache-2.0
/// The sheet the channel header's pin pill opens: every message currently
/// pinned in this channel, newest pin first, with an unpin action for
/// whoever the server lets use it (a failed attempt is just left in place -
/// the button that caused it is still right there to retry).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/pins_controller.dart';
import 'user_avatar.dart';

Future<void> showPinnedMessagesSheet(BuildContext context, String channelId) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _PinnedMessagesSheet(channelId: channelId),
  );
}

/// Never the raw id: see message_row_identity.dart's `_authorLabel` for the
/// same rule applied to the local store's own `Message`. Duplicated rather
/// than shared because [PinnedMessage.message] is the wire `api.Message`, a
/// different type from the local one that helper reads.
String _authorLabel(api.Message message) =>
    message.authorDisplayName ??
    (message.authorId == null ? 'Deleted user' : 'Unknown');

class _PinnedMessagesSheet extends ConsumerWidget {
  const _PinnedMessagesSheet({required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final pins = ref.watch(pinsControllerProvider(channelId));

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
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
                  AppIcons.pin,
                  size: AppSizes.icon16,
                  color: tokens.textSecondary,
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  'Pinned messages',
                  style: AppText.body.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: AppWeights.semi,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _Body(channelId: channelId, pins: pins),
          ),
        ],
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.channelId, required this.pins});

  final String channelId;
  final PinsState pins;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final list = pins.pinned;

    // A failed refresh with an older list on hand falls through to that list
    // below instead: it is stale, not wrong, and the live events correct it.
    if (list == null && pins.failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                pins.forbidden
                    ? 'You do not have permission to see pins here.'
                    : 'Could not load pinned messages.',
                style: TextStyle(color: tokens.textSecondary),
                textAlign: TextAlign.center,
              ),
              if (!pins.forbidden) ...[
                const SizedBox(height: AppSpacing.s12),
                TextButton(
                  onPressed: () => ref
                      .read(pinsControllerProvider(channelId).notifier)
                      .refresh(),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (list == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (list.isEmpty) {
      return Center(
        child: Text(
          'Nothing pinned yet.',
          style: TextStyle(color: tokens.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final pin = list[i];
        return ListTile(
          leading: AuthorAvatar(
            userId: pin.message.authorId,
            name: _authorLabel(pin.message),
            size: AppSizes.icon20 + 8,
          ),
          title: Text(_authorLabel(pin.message)),
          subtitle: Text(
            pin.message.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: AppIconButton(
            icon: AppIcons.pin,
            semanticLabel: 'Unpin this message',
            tooltip: 'Unpin',
            onPressed: () => ref
                .read(pinsControllerProvider(channelId).notifier)
                .unpin(pin.message.id),
          ),
        );
      },
    );
  }
}
