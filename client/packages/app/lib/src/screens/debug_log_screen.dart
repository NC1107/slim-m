// SPDX-License-Identifier: Apache-2.0
/// The debug log: what the app caught, newest first, with a copy button.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../diagnostics/debug_log.dart';

class DebugLogScreen extends ConsumerWidget {
  const DebugLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(debugLogProvider);
    final log = ref.read(debugLogProvider.notifier);
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Debug log'),
        actions: [
          IconButton(
            icon: const Icon(AppIcons.copy),
            tooltip: 'Copy all',
            onPressed: entries.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: log.asReport()),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Debug log copied')),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(AppIcons.delete),
            tooltip: 'Clear',
            onPressed: entries.isEmpty ? null : log.clear,
          ),
        ],
      ),
      body: entries.isEmpty
          ? const _Empty()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) =>
                  _EntryTile(entry: entries[i], tokens: tokens),
            ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.info, size: 28, color: tokens.textSecondary),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'Nothing has gone wrong this session.',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              'Errors the app catches are collected here so you can copy '
              'them into a bug report.',
              textAlign: TextAlign.center,
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.tokens});

  final DiagnosticEvent entry;
  final AppTokens tokens;

  Color get _levelColor => switch (entry.level) {
    DiagnosticSeverity.error => tokens.dangerText,
    DiagnosticSeverity.warning => tokens.warnText,
    DiagnosticSeverity.info => tokens.textSecondary,
  };

  @override
  Widget build(BuildContext context) {
    final header = Row(
      children: [
        Text(
          entry.timestamp,
          style: AppText.micro.copyWith(
            color: tokens.textSecondary,
            fontFamily: AppFonts.mono,
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Text(
          entry.source,
          style: AppText.micro.copyWith(
            color: _levelColor,
            fontWeight: AppWeights.semi,
          ),
        ),
      ],
    );

    final body = Text(entry.message, style: AppText.caption);

    if (entry.detail == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16,
          vertical: AppSpacing.s8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [header, const SizedBox(height: 2), body],
        ),
      );
    }

    return ExpansionTile(
      // Its own controller reads the platform's own reduce-motion feature, never this app's MotionOverride; see sheet.dart's library doc.
      expansionAnimationStyle: AppMotion.isReduced(context)
          ? AnimationStyle.noAnimation
          : null,
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 2), body],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            0,
            AppSpacing.s16,
            AppSpacing.s12,
          ),
          child: SelectableText(
            entry.detail!,
            style: AppText.code.copyWith(color: tokens.textSecondary),
          ),
        ),
      ],
    );
  }
}
