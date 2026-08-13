// SPDX-License-Identifier: Apache-2.0
/// The composer's action bar: attach, the field itself, and (space
/// permitting) poll, code, emoji and send.
///
/// Split out of `composer.dart`, already near its line budget. Presentational
/// only, like `ComposerField` and `ComposerBanners` beside it: every handler
/// is a plain callback the composer's own state already owns.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'composer_extras.dart';
import 'poll_composer_sheet.dart';

class ComposerActionBar extends StatelessWidget {
  const ComposerActionBar({
    super.key,
    required this.touch,
    required this.controller,
    required this.focusNode,
    required this.channelId,
    required this.channelName,
    required this.hasText,
    required this.canSend,
    required this.onSend,
    required this.onTyping,
    required this.onOpenActions,
    required this.onPickFile,
    required this.onSendPressed,
    required this.onInsertCode,
    required this.onPickEmoji,
    required this.gifSearchEnabled,
    required this.onPickGif,
  });

  final bool touch;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String channelId;
  final String channelName;
  final bool hasText;

  /// Whether this deployment offers GIF search at all
  /// (`Version.gifSearchEnabled`); the desktop icon button is absent, not
  /// disabled, when it does not.
  final bool gifSearchEnabled;
  final VoidCallback onPickGif;

  /// Whether [onSendPressed] is offered at all right now; see
  /// `composer.dart`'s own `_canSend` for everything that feeds it.
  final bool canSend;
  final Future<void> Function() onSend;
  final ValueChanged<String> onTyping;
  final VoidCallback onOpenActions;
  final VoidCallback onPickFile;
  final VoidCallback onSendPressed;
  final VoidCallback onInsertCode;
  final VoidCallback onPickEmoji;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // A line break grows the bar over a beat, earlier lines holding still.
    return MaybeAnimatedSize(
      duration: AppMotion.fast,
      curve: AppMotion.entrance,
      alignment: Alignment.topCenter,
      child: Container(
        key: const Key('composer-action-bar'),
        padding: const EdgeInsets.fromLTRB(12, 5, 10, 5),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Row(
          // Top, not centred: a centred icon drifts as the field grows.
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconButton(
              icon: AppIcons.add,
              semanticLabel: touch ? 'More actions' : 'Attach a file',
              tooltip: touch ? 'More actions' : 'Attach a file',
              onPressed: touch ? onOpenActions : onPickFile,
            ),
            const SizedBox(width: AppSpacing.s8),
            Expanded(
              child: ComposerField(
                controller: controller,
                focusNode: focusNode,
                channelName: channelName,
                hasText: hasText,
                onSend: onSend,
                onTyping: onTyping,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            // Behind the add button at touch density; see `showComposerActionsSheet`.
            if (!touch) ...[
              AppIconButton(
                icon: AppIcons.poll,
                semanticLabel: 'Create a poll',
                tooltip: 'Create a poll',
                onPressed: () => showPollComposerSheet(context, channelId),
              ),
              AppIconButton(
                icon: AppIcons.code,
                semanticLabel: 'Insert code',
                tooltip: 'Insert code',
                onPressed: onInsertCode,
              ),
              if (gifSearchEnabled)
                AppIconButton(
                  icon: AppIcons.gif,
                  semanticLabel: 'Insert a GIF',
                  tooltip: 'Insert a GIF',
                  onPressed: onPickGif,
                ),
            ],
            AppIconButton(
              icon: AppIcons.smile,
              semanticLabel: 'Insert emoji',
              tooltip: 'Insert emoji',
              onPressed: onPickEmoji,
            ),
            // Always rendered, only disabled when empty or over the limit.
            AppIconButton(
              icon: AppIcons.send,
              semanticLabel: 'Send message',
              tooltip: 'Send message',
              onPressed: canSend ? onSendPressed : null,
            ),
          ],
        ),
      ),
    );
  }
}
