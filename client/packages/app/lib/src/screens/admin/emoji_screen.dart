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
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../../routing/close_screen.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/custom_emoji_image.dart';
import 'emoji_upload_card.dart';

class EmojiScreen extends ConsumerWidget {
  const EmojiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emoji = ref.watch(customEmojiProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emoji'),
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          tooltip: 'Back to Space settings',
          onPressed: () => closeScreen(context, Routes.spaceSettings),
        ),
      ),
      // top: false because the AppBar already clears the status bar.
      body: AppContentColumn(
        child: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.s16),
            children: [
              const EmojiUploadCard(),
              const SizedBox(height: AppSpacing.s16),
              emoji.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _Message('Could not load emoji. $e'),
                data: (list) => list.isEmpty
                    ? const _Message('No emoji yet.')
                    : Column(
                        children: [
                          for (final item in list) ...[
                            _EmojiRow(emoji: item),
                            const SizedBox(height: AppSpacing.s8),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
      child: Text(text, style: TextStyle(color: tokens.textSecondary)),
    );
  }
}

class _EmojiRow extends ConsumerStatefulWidget {
  const _EmojiRow({required this.emoji});

  final api.CustomEmoji emoji;

  @override
  ConsumerState<_EmojiRow> createState() => _EmojiRowState();
}

class _EmojiRowState extends ConsumerState<_EmojiRow> {
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
    try {
      await ref.read(apiProvider).deleteCustomEmoji(widget.emoji.id);
      if (context.mounted) ref.invalidate(customEmojiProvider);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove $shortcode. ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final emoji = widget.emoji;

    return AppCard(
      child: Row(
        children: [
          // The same widget and the same cache a message row draws it
          // through, so this list shows what a member will actually see.
          CustomEmojiImage(emojiId: emoji.id, size: 32),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  emoji.shortcode,
                  style: const TextStyle(fontFamily: AppFonts.mono),
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  'Added ${formatDateTime(emoji.createdAt)}',
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: AppIcons.delete,
            semanticLabel: 'Remove ${emoji.shortcode}',
            variant: AppIconButtonVariant.danger,
            onPressed: _busy ? null : _delete,
          ),
        ],
      ),
    );
  }
}
