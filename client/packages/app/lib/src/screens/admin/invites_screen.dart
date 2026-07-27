// SPDX-License-Identifier: Apache-2.0
/// Invite management: `GET/POST /invites` and `DELETE /invites/{code}`.
/// Requires CREATE_INVITE.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../format.dart';
import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../../widgets/confirm_dialog.dart';

const _expiryOptions = <(String, Duration?)>[
  ('Never', null),
  ('1 day', Duration(days: 1)),
  ('7 days', Duration(days: 7)),
  ('30 days', Duration(days: 30)),
];

class InvitesScreen extends ConsumerWidget {
  const InvitesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invites = ref.watch(invitesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invites'),
        leading: IconButton(
          icon: const Icon(AppIcons.back),
          tooltip: 'Back to settings',
          onPressed: () => context.go(Routes.settings),
        ),
      ),
      // top: false because the AppBar already clears the status bar.
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s16),
          children: [
            const _CreateInviteCard(),
            const SizedBox(height: AppSpacing.s16),
            invites.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _Message('Could not load invites. $e'),
              data: (list) => list.isEmpty
                  ? const _Message('No invites yet.')
                  : Column(
                      children: [
                        for (final invite in list) ...[
                          _InviteRow(invite: invite),
                          const SizedBox(height: AppSpacing.s8),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
      child: Text(text, style: TextStyle(color: tokens.textSecondary)),
    );
  }
}

class _CreateInviteCard extends ConsumerStatefulWidget {
  const _CreateInviteCard();

  @override
  ConsumerState<_CreateInviteCard> createState() => _CreateInviteCardState();
}

class _CreateInviteCardState extends ConsumerState<_CreateInviteCard> {
  final _maxUses = TextEditingController();
  int _expiryIndex = 0;
  bool _submitting = false;
  api.Invite? _created;

  @override
  void dispose() {
    _maxUses.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _submitting = true);
    final maxUses = int.tryParse(_maxUses.text.trim());
    final duration = _expiryOptions[_expiryIndex].$2;
    final expiresAt = duration == null
        ? null
        : DateTime.now().add(duration).millisecondsSinceEpoch;
    try {
      final invite = await ref.read(apiProvider).createInvite(
            maxUses: maxUses,
            expiresAt: expiresAt,
          );
      if (context.mounted) ref.invalidate(invitesProvider);
      if (!mounted) return;
      setState(() {
        _created = invite;
        _submitting = false;
        _maxUses.clear();
        _expiryIndex = 0;
      });
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create the invite. ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: 'New invite',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_created != null) ...[
            _CreatedInviteCallout(
              invite: _created!,
              onDismiss: () => setState(() => _created = null),
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
          AppInput(
            controller: _maxUses,
            placeholder: 'Uses allowed (blank for unlimited)',
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: AppSpacing.s12),
          AppSegmentedControl.inline(
            semanticLabel: 'Invite expiry',
            options: [
              for (final option in _expiryOptions)
                AppSegmentedOption(label: option.$1),
            ],
            selectedIndex: _expiryIndex,
            onSegmentSelected: (i) => setState(() => _expiryIndex = i),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppButton(
            label: _submitting ? 'Creating...' : 'Create invite',
            icon: AppIcons.invite,
            variant: AppButtonVariant.primary,
            full: true,
            disabled: _submitting,
            onPressed: _create,
          ),
        ],
      ),
    );
  }
}

class _CreatedInviteCallout extends StatelessWidget {
  const _CreatedInviteCallout({required this.invite, required this.onDismiss});

  final api.Invite invite;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return AppCallout(
      tone: AppCalloutTone.accent,
      child: Row(
        children: [
          Expanded(
            child: Text(invite.code,
                style: const TextStyle(fontFamily: AppFonts.mono)),
          ),
          AppIconButton(
            icon: AppIcons.copy,
            semanticLabel: 'Copy invite code',
            size: AppIconButtonSize.sm,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: invite.code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite code copied.')),
              );
            },
          ),
          AppIconButton(
            icon: AppIcons.dismiss,
            semanticLabel: 'Dismiss',
            size: AppIconButtonSize.sm,
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}

class _InviteRow extends ConsumerStatefulWidget {
  const _InviteRow({required this.invite});

  final api.Invite invite;

  @override
  ConsumerState<_InviteRow> createState() => _InviteRowState();
}

class _InviteRowState extends ConsumerState<_InviteRow> {
  bool _busy = false;

  Future<void> _revoke() async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Revoke this invite?',
      message: 'Anyone holding "${widget.invite.code}" will no longer be '
          'able to redeem it. This cannot be undone.',
      confirmLabel: 'Revoke',
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).revokeInvite(widget.invite.code);
      if (context.mounted) ref.invalidate(invitesProvider);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not revoke the invite. ${e.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final invite = widget.invite;
    final usesLabel = invite.maxUses == null
        ? '${invite.uses} uses'
        : '${invite.uses}/${invite.maxUses} uses';
    final expiryLabel = invite.expiresAt == null
        ? 'Never expires'
        : 'Expires ${formatDateTime(invite.expiresAt!)}';

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(invite.code,
                        style: const TextStyle(fontFamily: AppFonts.mono)),
                    const SizedBox(width: AppSpacing.s8),
                    if (invite.revoked)
                      const AppBadge(
                          variant: AppBadgeVariant.warn, label: 'Revoked')
                    else if (!invite.usable)
                      const AppBadge(
                          variant: AppBadgeVariant.tag, label: 'Expired'),
                  ],
                ),
                const SizedBox(height: AppSpacing.s4),
                Text('$usesLabel · $expiryLabel',
                    style:
                        AppText.caption.copyWith(color: tokens.textSecondary)),
              ],
            ),
          ),
          if (!invite.revoked)
            AppIconButton(
              icon: AppIcons.revoke,
              semanticLabel: 'Revoke invite',
              variant: AppIconButtonVariant.danger,
              onPressed: _busy ? null : _revoke,
            ),
        ],
      ),
    );
  }
}
