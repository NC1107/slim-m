// SPDX-License-Identifier: Apache-2.0
/// Custom emoji administration: `GET/POST /emoji` and `DELETE /emoji/{id}`.
/// Requires MANAGE_SERVER, the bit that already means "change what this
/// deployment is".
///
/// Reading the list is open to every member server-side, so the permission
/// this screen is gated on is about the two write actions on it, not about
/// seeing which emoji exist.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../format.dart';
import '../../providers/admin_providers.dart';
import '../../providers/display_preferences.dart';
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../settings_screen_scaffold.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/custom_emoji_image.dart';
import '../../widgets/run_guarded.dart';
import '../../widgets/settings_entity_row.dart';
import '../../widgets/settings_section_header.dart';
import 'emoji_upload_card.dart';

class EmojiScreen extends ConsumerWidget {
  const EmojiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emoji = ref.watch(customEmojiProvider);

    return SettingsScreenScaffold(
      title: 'Emoji',
      backTooltip: 'Back to Space settings',
      backFallback: Routes.spaceSettings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EmojiUploadCard(),
          const SizedBox(height: AppSpacing.s16),
          AppAsyncView<List<api.CustomEmoji>>(
            value: AppAsyncState(data: emoji.valueOrNull, error: emoji.error),
            center: false,
            errorMessage: 'Could not load emoji.',
            onRetry: () => ref.invalidate(customEmojiProvider),
            isEmpty: (list) => list.isEmpty,
            emptyMessage: 'No emoji yet.',
            data: (context, list) => SettingsSectionCard(
              title: 'Emoji',
              children: [for (final item in list) _EmojiRow(emoji: item)],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiRow extends ConsumerStatefulWidget {
  const _EmojiRow({required this.emoji});

  final api.CustomEmoji emoji;

  @override
  ConsumerState<_EmojiRow> createState() => _EmojiRowState();
}

class _EmojiRowState extends ConsumerState<_EmojiRow>
    with GuardedActionState<_EmojiRow> {
  bool _busy = false;

  Future<void> _delete() async {
    final shortcode = widget.emoji.shortcode;
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Remove $shortcode?',
      message:
          'Messages that already use it keep their text, but it stops '
          'rendering as an image. This cannot be undone.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    final ok = await guard(
      // Not "remove $shortcode": a shortcode's own trailing colon collides with the one some failure sentences end in.
      whatFailed: 'remove the $shortcode emoji',
      action: () => ref.read(apiProvider).deleteCustomEmoji(widget.emoji.id),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.invalidate(customEmojiProvider);
  }

  @override
  Widget build(BuildContext context) {
    final emoji = widget.emoji;

    return SettingsEntityRow(
      // The same widget and the same cache a message row draws it through, so this list shows what a member will actually see.
      leading: CustomEmojiImage(emojiId: emoji.id, size: 32),
      headline: emoji.shortcode,
      headlineStyle: AppText.code,
      details: [
        SettingsEntityDetail(
          'Added ${formatDateTime(emoji.createdAt, use24Hour: watchUse24Hour(ref, context))}',
        ),
      ],
      actions: [
        AppIconButton(
          icon: AppIcons.delete,
          semanticLabel: 'Remove ${emoji.shortcode}',
          variant: AppIconButtonVariant.danger,
          onPressed: _busy ? null : _delete,
        ),
      ],
      error: actionError,
      onErrorDismiss: clearActionError,
    );
  }
}
