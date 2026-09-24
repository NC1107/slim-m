// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A bot's profile section: its prefix and registered commands, so someone
/// can learn a bot without being told. See
/// docs/decisions/0031-bot-command-registration.md.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/bot_commands.dart';

/// Rows beyond this collapse into a "+N more" line, so a bot with a large
/// command set cannot blow out the popover's own measured-collision layout.
const int _maxShown = 8;

class MemberProfileBotCommands extends ConsumerWidget {
  const MemberProfileBotCommands({super.key, required this.botId});

  final String botId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registration = ref
        .watch(botCommandRegistrationProvider(botId))
        .valueOrNull;
    final commands = registration?.commands ?? const [];
    if (registration?.prefix == null || commands.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final shown = commands.take(_maxShown).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        0,
        AppSpacing.s12,
        AppSpacing.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Commands - answers to ${registration!.prefix}',
            style: AppText.label.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s4),
          for (final command in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s4),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${registration.prefix}${command.name} ',
                      style: AppText.code.copyWith(color: tokens.textPrimary),
                    ),
                    TextSpan(
                      text: command.description,
                      style: AppText.caption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (commands.length > _maxShown)
            Text(
              '+${commands.length - _maxShown} more',
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
        ],
      ),
    );
  }
}
