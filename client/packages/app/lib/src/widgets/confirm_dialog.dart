// SPDX-License-Identifier: Apache-2.0
/// A destructive-action confirmation, shared by the moderation and
/// administration screens rather than each hand-rolling its own dialog.
///
/// Routed through [showAppSheet] rather than a bare `AlertDialog`, so it gets
/// the same border-first card, radius and phone/desktop split every other
/// modal in the app already has - a raw `AlertDialog` draws Material's own
/// 28dp-radius, shadowed card, which reads as a different app mid-flow.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// The shared confirmation copy for deleting a message, used identically by
/// `channel_message_actions.dart` (a message's own actions menu) and
/// `report_card_actions.dart` (a moderator deleting a reported message) - one
/// constant rather than two call sites hand-typing the same words, so an
/// edit to one cannot leave the other one word off without changing both.
const String deleteMessageConfirmTitle = 'Delete message?';
const String deleteMessageConfirmMessage =
    'This removes it for everyone in the channel. This cannot be undone.';

/// Asks before a destructive, hard-to-undo action. [message] must state what
/// happens, not just ask "are you sure?".
///
/// [cancelLabel] names the way out where "Cancel" is vaguer than the choice
/// deserves. Its absence is why one caller copied this whole dialog rather
/// than reuse it.
Future<bool> confirmDangerousAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final confirmed = await showAppSheet<bool>(
    context,
    builder: (context) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
    ),
  );
  return confirmed ?? false;
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppText.body.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            message,
            style: AppText.body.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s16),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: cancelLabel,
                  variant: AppButtonVariant.ghost,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                // Danger is outlined, never filled: the destructive choice
                // must be unmistakable without being the brightest thing on
                // screen.
                child: AppButton(
                  label: confirmLabel,
                  variant: AppButtonVariant.danger,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
