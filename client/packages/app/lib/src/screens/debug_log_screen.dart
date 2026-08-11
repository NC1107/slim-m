// SPDX-License-Identifier: Apache-2.0
/// The debug log: what the app caught, newest first, with a copy button.
///
/// This screen used to build its own `Scaffold`/`AppBar` rather than going
/// through [SettingsScreenScaffold] like its eleven siblings, which cost it
/// two things. It lost [BackToButton]'s named "Back to X" tooltip, leaving a
/// bare default arrow that says nothing about where it goes - a real
/// accessibility regression, since the tooltip is the only thing that names
/// the destination. And it bypassed [AppContentColumn], so nothing tied its
/// content width to the screens it sits beside.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../diagnostics/debug_log.dart';
import '../routing/routes.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/settings_notice.dart';
import '../widgets/settings_section_header.dart';
import 'settings_screen_scaffold.dart';

class DebugLogScreen extends ConsumerWidget {
  const DebugLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(debugLogProvider);
    final log = ref.read(debugLogProvider.notifier);

    return SettingsScreenScaffold(
      title: 'Debug log',
      backTooltip: 'Back to settings',
      backFallback: Routes.personalSettings,
      actions: [
        IconButton(
          icon: const Icon(AppIcons.copy),
          tooltip: 'Copy all',
          onPressed: entries.isEmpty
              ? null
              : () async {
                  await Clipboard.setData(ClipboardData(text: log.asReport()));
                  if (!context.mounted) return;
                  showAppSnackbar(context, 'Debug log copied');
                },
        ),
        IconButton(
          icon: const Icon(AppIcons.delete),
          tooltip: 'Clear',
          onPressed: entries.isEmpty ? null : log.clear,
        ),
      ],
      child: entries.isEmpty
          ? const SettingsNotice(
              message: 'Nothing has gone wrong this session.',
              detail:
                  'Errors the app catches are collected here so you can copy '
                  'them into a bug report.',
            )
          : SettingsSectionCard(
              title: 'This session',
              description: '${entries.length} caught, newest first.',
              children: [for (final entry in entries) _EntryTile(entry: entry)],
            ),
    );
  }
}

/// One caught event.
///
/// Severity used to be carried by the category label's colour alone - the one
/// place in this whole area that encoded state in a single channel, against
/// this project's standing rule that a cue never rides on colour by itself
/// (see `AppStatusDot`, which pairs every colour with its own shape). The
/// label text is the *source* ("flutter", "platform", "voice"), not the
/// severity, and the same source logs at any severity depending on context,
/// so there was no redundant cue anywhere on the row. A leading glyph and a
/// spoken severity word carry it now, and the colour is a third reinforcement
/// rather than the only one.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final DiagnosticEvent entry;

  Color _levelColor(AppTokens tokens) => switch (entry.level) {
    DiagnosticSeverity.error => tokens.dangerText,
    DiagnosticSeverity.warning => tokens.warnText,
    DiagnosticSeverity.info => tokens.textSecondary,
  };

  /// Three distinct silhouettes, not three tints of one: an octagon, a
  /// triangle and a circle, the same shape-carries-the-state treatment
  /// `AppStatusDot` gives presence.
  IconData get _levelIcon => switch (entry.level) {
    DiagnosticSeverity.error => AppIcons.danger,
    DiagnosticSeverity.warning => AppIcons.warning,
    DiagnosticSeverity.info => AppIcons.info,
  };

  String get _levelWord => switch (entry.level) {
    DiagnosticSeverity.error => 'Error',
    DiagnosticSeverity.warning => 'Warning',
    DiagnosticSeverity.info => 'Info',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final level = _levelColor(tokens);

    final header = Row(
      children: [
        Icon(_levelIcon, size: AppSizes.icon16, color: level),
        const SizedBox(width: AppSpacing.s8),
        // Spoken and shown: the glyph alone still leaves severity to a shape.
        Text(
          _levelWord,
          style: AppText.micro.copyWith(
            color: level,
            fontWeight: AppWeights.semi,
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Flexible(
          child: Text(
            entry.source,
            overflow: TextOverflow.ellipsis,
            style: AppText.micro.copyWith(color: tokens.textSecondary),
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        Text(
          entry.timestamp,
          style: AppText.micro.copyWith(
            color: tokens.textSecondary,
            fontFamily: AppFonts.mono,
          ),
        ),
      ],
    );

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        const SizedBox(height: 2),
        Text(entry.message, style: AppText.caption),
      ],
    );

    if (entry.detail == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s8,
        ),
        child: title,
      );
    }

    return ExpansionTile(
      // Its own controller reads the platform's own reduce-motion feature, never this app's MotionOverride; see sheet.dart's library doc.
      expansionAnimationStyle: AppMotion.isReduced(context)
          ? AnimationStyle.noAnimation
          : null,
      tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      shape: const Border(),
      collapsedShape: const Border(),
      title: title,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s8,
            0,
            AppSpacing.s8,
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
