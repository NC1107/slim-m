// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The persistent record of a failed action.
///
/// The error grammar's rule is that a failure is a state, not an event: it
/// appears at the point of the action, stays until something changes it, and
/// always ships a verb. A `SnackBar` breaks all three - it floats away from
/// the control, vanishes on a timer, and leaves nothing behind, which is
/// exactly how a failed account deletion or a failed block became invisible
/// a few seconds later.
///
/// [autoDismissAfter] is the one deliberate exception, and a narrow one: a
/// low-stakes, self-correcting action failure the user does not have to act
/// on - a gif that would not attach, say - may fade itself after a beat
/// rather than sitting until dismissed. This stays an `AppErrorState`, not a
/// `SnackBar`: it still appears at the point of the action and still ships a
/// verb, it just does not outlive its own relevance. Never set it for a
/// failure the user must notice or resolve (a failed send, deletion or
/// block); those are exactly the "invisible a few seconds later" case above.
///
/// Red is outlined, never filled: a destructive or failed state must be
/// unmistakable without being the brightest thing on the screen. That is why
/// this draws a hairline in [AppTokens.dangerBorder] over the ordinary
/// surface rather than a red fill.
library;

import 'dart:async';

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
class AppErrorState extends StatefulWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.detail,
    this.onRetry,
    this.retryLabel = 'Retry',
    this.onDismiss,
    this.dismissLabel = 'Dismiss',
    this.autoDismissAfter,
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

  /// When set (with [onDismiss]), fires [onDismiss] itself after this delay,
  /// so a transient failure clears without a click. See the library doc for
  /// the narrow case this is meant for; leave it null for anything the user
  /// must act on.
  final Duration? autoDismissAfter;

  @override
  State<AppErrorState> createState() => _AppErrorStateState();
}

class _AppErrorStateState extends State<AppErrorState> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _armAutoDismiss();
  }

  @override
  void didUpdateWidget(AppErrorState old) {
    super.didUpdateWidget(old);
    // A new message (or a newly-armed timer) restarts the countdown, so a second failure gets its own full delay rather than inheriting the first's remainder.
    if (old.message != widget.message ||
        old.autoDismissAfter != widget.autoDismissAfter) {
      _timer?.cancel();
      _armAutoDismiss();
    }
  }

  void _armAutoDismiss() {
    final after = widget.autoDismissAfter;
    final onDismiss = widget.onDismiss;
    if (after == null || onDismiss == null) return;
    _timer = Timer(after, onDismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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
                    widget.message,
                    style: AppText.caption.copyWith(color: tokens.dangerText),
                  ),
                ),
              ],
            ),
            if (widget.detail != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                widget.detail!,
                style: AppText.code.copyWith(color: tokens.textSecondary),
              ),
            ],
            if (widget.onRetry != null || widget.onDismiss != null) ...[
              const SizedBox(height: AppSpacing.s12),
              Wrap(
                spacing: AppSpacing.s8,
                children: [
                  if (widget.onRetry != null)
                    AppButton(
                      label: widget.retryLabel,
                      size: AppButtonSize.sm,
                      variant: AppButtonVariant.danger,
                      onPressed: widget.onRetry,
                    ),
                  if (widget.onDismiss != null)
                    AppButton(
                      label: widget.dismissLabel,
                      size: AppButtonSize.sm,
                      onPressed: widget.onDismiss,
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
