// SPDX-License-Identifier: Apache-2.0
/// The sheet shown once after an update: what changed since whichever
/// version was last seen on this install.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../whats_new/whats_new_content.dart';

/// Shows [entries], newest first: someone catching up after skipping a few
/// releases cares most about the latest, and [entries] itself is kept in the
/// chronological order it was authored in so this is the one place that
/// reverses it for display.
Future<void> showWhatsNewSheet(
  BuildContext context,
  List<WhatsNewEntry> entries,
) {
  return showAppSheet<void>(
    context,
    scrolls: true,
    builder: (context) =>
        _WhatsNewSheet(entries: entries.reversed.toList(growable: false)),
  );
}

class _WhatsNewSheet extends StatelessWidget {
  const _WhatsNewSheet({required this.entries});

  final List<WhatsNewEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  AppIcons.highlight,
                  size: AppSizes.icon20,
                  color: tokens.accent,
                ),
                const SizedBox(width: AppSpacing.s8),
                Text(
                  "What's new",
                  style: AppText.heading.copyWith(color: tokens.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final entry in entries)
                      _WhatsNewEntrySection(entry: entry),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s16),
            AppButton(
              label: 'Got it',
              variant: AppButtonVariant.primary,
              full: true,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WhatsNewEntrySection extends StatelessWidget {
  const _WhatsNewEntrySection({required this.entry});

  final WhatsNewEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.headline,
            style: AppText.ui.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final point in entry.points)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s8),
              child: point.warn
                  ? AppCallout(
                      tone: AppCalloutTone.warn,
                      child: Text(point.body),
                    )
                  : _Bullet(text: point.body),
            ),
        ],
      ),
    );
  }
}

/// A plain highlight, styled the way every other secondary-information line
/// in this app is: [AppText.body] at [AppTokens.textSecondary].
class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final style = AppText.body.copyWith(color: tokens.textSecondary);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•  ', style: style),
        Expanded(child: Text(text, style: style)),
      ],
    );
  }
}
