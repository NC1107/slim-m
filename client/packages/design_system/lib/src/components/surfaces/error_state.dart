// SPDX-License-Identifier: Apache-2.0
/// The persistent record of a failed action.
///
/// The error grammar's rule is that a failure is a state, not an event: it
/// appears at the point of the action, stays until something changes it, and
/// always ships a verb. A `SnackBar` breaks all three - it floats away from
/// the control, vanishes on a timer, and leaves nothing behind, which is
/// exactly how a failed account deletion or a failed block became invisible
/// a few seconds later.
///
/// Red is outlined, never filled: a destructive or failed state must be
/// unmistakable without being the brightest thing on the screen. That is why
/// this draws a hairline in [AppTokens.dangerBorder] over the ordinary
/// surface rather than a red fill.
library;

import 'package:flutter/material.dart';

import '../../app_icons.dart';
import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';
import '../core/button.dart';

/// An inline failure with a way forward.
///
/// [detail] is for the technical line the person running the server wants
/// (a status code, a limit, a host) and renders in mono: present, not
/// shouting. [onRetry] and [onDismiss] are both optional, but a failure with
/// neither is usually a failure the caller should not be showing at all.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.detail,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.onDismiss,
    this.dismissLabel = 'Dismiss',
  });

  /// What happened, in plain words, and what it means for the user. Never a
  /// raw exception.
  final String message;

  /// Optional technical detail, rendered in mono beneath the message.
  final String? detail;

  final VoidCallback? onRetry;
  final String retryLabel;
  final VoidCallback? onDismiss;
  final String dismissLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.s12),
        decoration: BoxDecoration(
          border: Border.all(color: tokens.dangerBorder),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  AppIcons.failed,
                  size: AppSizes.icon16,
                  color: tokens.dangerText,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Text(
                    message,
                    style: AppText.caption.copyWith(color: tokens.dangerText),
                  ),
                ),
              ],
            ),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                detail!,
                style: AppText.code.copyWith(color: tokens.textSecondary),
              ),
            ],
            if (onRetry != null || onDismiss != null) ...[
              const SizedBox(height: AppSpacing.s12),
              Wrap(
                spacing: AppSpacing.s8,
                children: [
                  if (onRetry != null)
                    AppButton(
                      label: retryLabel,
                      size: AppButtonSize.sm,
                      variant: AppButtonVariant.danger,
                      onPressed: onRetry,
                    ),
                  if (onDismiss != null)
                    AppButton(
                      label: dismissLabel,
                      size: AppButtonSize.sm,
                      onPressed: onDismiss,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
