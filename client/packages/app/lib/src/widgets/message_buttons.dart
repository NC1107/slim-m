// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The rows of buttons a bot attaches to its message. See
/// docs/decisions/0039-bot-message-buttons.md.
///
/// Layout follows the width it is given, never the platform: a row wraps
/// rather than scrolling, so five buttons fit a phone as two lines.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/button_presses.dart';
import 'embed_card.dart' show launchIfHttp;

/// A failure stays a readable line under the row, not a full-width banner.
const double _errorMaxWidth = 480;

AppButtonVariant _variantFor(api.ComponentButtonStyle style) => switch (style) {
  // Soft, not filled: several may share a message and only one action per screen is filled.
  api.ComponentButtonStyle.primary => AppButtonVariant.soft,
  api.ComponentButtonStyle.secondary => AppButtonVariant.secondary,
  api.ComponentButtonStyle.danger => AppButtonVariant.danger,
  api.ComponentButtonStyle.link => AppButtonVariant.ghost,
};

/// [unavailable] disables every button, for a message whose bot is gone.
class MessageButtons extends ConsumerWidget {
  const MessageButtons({
    super.key,
    required this.channelId,
    required this.messageId,
    required this.rows,
    this.unavailable = false,
  });

  final String channelId;
  final String messageId;
  final List<api.ComponentRow> rows;
  final bool unavailable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final presses = ref.watch(messageButtonPressesProvider(messageId));
    final controller = ref.read(buttonPressesProvider.notifier);
    void press(String customId) => unawaited(
      controller.press(
        channelId: channelId,
        messageId: messageId,
        customId: customId,
      ),
    );
    final failed = presses.values
        .where((p) => p.status == ButtonPressStatus.failed)
        .firstOrNull;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMessageColumnMax),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  for (final button in row.buttons)
                    _ButtonView(
                      button: button,
                      pending: presses[button.customId]?.pending ?? false,
                      disabled: unavailable || button.disabled,
                      onPressed: button.customId == null
                          ? null
                          : () => press(button.customId!),
                    ),
                ],
              ),
            ),
          if (failed != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.s8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _errorMaxWidth),
                child: AppErrorState(
                  message: failed.failure ?? 'That button did not work.',
                  onRetry: () {
                    controller.dismiss(messageId, failed.customId);
                    press(failed.customId);
                  },
                  onDismiss: () =>
                      controller.dismiss(messageId, failed.customId),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ButtonView extends StatelessWidget {
  const _ButtonView({
    required this.button,
    required this.pending,
    required this.disabled,
    required this.onPressed,
  });

  final api.MessageButton button;
  final bool pending;
  final bool disabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final isLink = button.style == api.ComponentButtonStyle.link;
    final url = button.url;
    AppButton build({required bool busy}) => AppButton(
      label: button.label,
      variant: _variantFor(button.style),
      size: AppButtonSize.sm,
      icon: isLink ? AppIcons.externalLink : null,
      disabled: disabled,
      busy: busy,
      onPressed: isLink
          ? (url == null ? null : () => unawaited(launchIfHttp(url)))
          : onPressed,
    );
    if (!pending) return build(busy: false);
    // The invisible copy holds the label's width so the spinner swaps in without a reflow.
    return Stack(
      children: [
        Visibility(
          visible: false,
          maintainSize: true,
          maintainState: true,
          maintainAnimation: true,
          child: build(busy: false),
        ),
        Positioned.fill(child: build(busy: true)),
      ],
    );
  }
}
