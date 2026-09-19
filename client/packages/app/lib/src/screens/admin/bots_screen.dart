// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Provisioning bots: making one, seeing what exists, and stopping one.
///
/// A bot is a member like any other, so this screen deliberately does not
/// manage what a bot may *do* - that is the roles screen, through the same
/// rows a person's permissions go through. All this owns is the credential.
/// See `docs/decisions/0028-bot-accounts.md`.
///
/// The token is shown once, here, immediately after creation, and is
/// unrecoverable afterwards because the server keeps only a hash. That is why
/// the reveal is a persistent card the operator dismisses rather than a toast:
/// a credential that vanishes on a timer is a credential somebody loses.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../../widgets/labeled_field.dart';
import '../../widgets/run_guarded.dart';
import '../../widgets/settings_entity_row.dart';
import '../../widgets/settings_notice.dart';
import '../../widgets/settings_section_header.dart';
import '../settings_screen_scaffold.dart';

class BotsScreen extends StatelessWidget {
  const BotsScreen({super.key});

  @override
  Widget build(BuildContext context) => const SettingsScreenScaffold(
    title: 'Bots',
    backTooltip: 'Back to Space settings',
    backFallback: Routes.spaceSettings,
    child: BotsPane(),
  );
}

class BotsPane extends ConsumerStatefulWidget {
  const BotsPane({super.key});

  @override
  ConsumerState<BotsPane> createState() => _BotsPaneState();
}

class _BotsPaneState extends ConsumerState<BotsPane>
    with GuardedActionState<BotsPane> {
  final _username = TextEditingController();
  bool _busy = false;

  /// The one and only time this token is legible. Held in state rather than
  /// pushed into a toast, so it stays on screen until it is dismissed.
  api.NewBot? _justCreated;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final username = _username.text.trim();
    if (username.isEmpty) return;
    setState(() => _busy = true);
    api.NewBot? created;
    final ok = await guard(
      whatFailed: 'create the bot',
      action: () async {
        created = await ref.read(apiProvider).createBot(username);
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _justCreated = created;
        _username.clear();
      }
    });
    if (ok) ref.invalidate(botsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final bots = ref.watch(botsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_justCreated case final created?) ...[
          _TokenReveal(
            created: created,
            onDismiss: () => setState(() => _justCreated = null),
          ),
          const SizedBox(height: AppSpacing.s16),
        ],
        const SettingsSectionHeader('Add a bot'),
        SettingsSectionCard(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: 'Username',
              helper:
                  'Letters, digits, _ . and - only. Up to 32 characters, the '
                  'same as a person.',
              child: AppInput(
                controller: _username,
                autocorrect: false,
                semanticLabel: 'Bot username',
                onSubmitted: (_) => _busy ? null : _create(),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            AppButton(
              label: 'Create bot',
              variant: AppButtonVariant.primary,
              onPressed: _busy ? null : _create,
            ),
            if (actionError case final error?) ...[
              const SizedBox(height: AppSpacing.s12),
              SettingsNotice(icon: AppIcons.warning, message: error),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.s24),
        const SettingsSectionHeader('Bots in this Space'),
        AppAsyncView<List<api.Bot>>(
          value: AppAsyncState(data: bots.valueOrNull, error: bots.error),
          center: false,
          errorMessage: 'Could not load the bots.',
          onRetry: () => ref.invalidate(botsProvider),
          isEmpty: (list) => list.isEmpty,
          emptyMessage: 'No bots yet.',
          data: (context, list) => SettingsSectionCard(
            children: [for (final bot in list) _BotRow(bot: bot)],
          ),
        ),
      ],
    );
  }
}

/// The created bot's token, shown once.
class _TokenReveal extends StatelessWidget {
  const _TokenReveal({required this.created, required this.onDismiss});

  final api.NewBot created;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return SettingsSectionCard(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsNotice(
          icon: AppIcons.warning,
          message:
              'This is the only time ${created.bot.username}\'s token is '
              'shown. Copy it now - the server keeps only a hash, so it '
              'cannot be shown again. Revoke the bot and make another if you '
              'lose it.',
        ),
        const SizedBox(height: AppSpacing.s12),
        SelectableText(
          created.token,
          style: AppText.code,
          semanticsLabel: 'Bot token for ${created.bot.username}',
        ),
        const SizedBox(height: AppSpacing.s12),
        Row(
          children: [
            AppButton(
              label: 'Copy token',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.sm,
              icon: AppIcons.copy,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: created.token)),
            ),
            const SizedBox(width: AppSpacing.s8),
            AppButton(
              label: 'Done',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.sm,
              onPressed: onDismiss,
            ),
          ],
        ),
      ],
    );
  }
}

class _BotRow extends ConsumerStatefulWidget {
  const _BotRow({required this.bot});

  final api.Bot bot;

  @override
  ConsumerState<_BotRow> createState() => _BotRowState();
}

class _BotRowState extends ConsumerState<_BotRow>
    with GuardedActionState<_BotRow> {
  bool _busy = false;

  Future<void> _revoke() async {
    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'revoke ${widget.bot.username}',
      action: () => ref.read(apiProvider).revokeBot(widget.bot.userId),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.invalidate(botsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final bot = widget.bot;

    return SettingsEntityRow(
      headline: bot.displayName,
      details: [
        SettingsEntityDetail('@${bot.username}'),
        if (bot.isRevoked)
          const SettingsAbsentValue('Revoked. Kept for what it wrote.')
        else if (bot.tokenLastUsedAt == null)
          const SettingsAbsentValue('Never used yet.')
        else
          const SettingsEntityDetail('Token active.'),
      ],
      actions: [
        if (!bot.isRevoked)
          AppButton(
            label: 'Revoke',
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.sm,
            onPressed: _busy ? null : _revoke,
          ),
      ],
      error: actionError,
      onErrorDismiss: clearActionError,
    );
  }
}
