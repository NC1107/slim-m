// SPDX-License-Identifier: Apache-2.0
/// The sheet the rail's per-section "+" opens: a name and a text/voice
/// choice, sent through `POST /channels` ([api.SlimmApi.createChannel]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../routing/routes.dart';

/// Opens the sheet, defaulting the kind picker to [initialKind] (the section
/// whose "+" was tapped): still changeable inside the sheet, since the
/// section is only a hint about intent, not a hard constraint the server
/// enforces.
Future<void> showCreateChannelSheet(
  BuildContext context, {
  required String initialKind,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) => _CreateChannelSheet(initialKind: initialKind),
  );
}

class _CreateChannelSheet extends ConsumerStatefulWidget {
  const _CreateChannelSheet({required this.initialKind});

  final String initialKind;

  @override
  ConsumerState<_CreateChannelSheet> createState() =>
      _CreateChannelSheetState();
}

class _CreateChannelSheetState extends ConsumerState<_CreateChannelSheet> {
  final _name = TextEditingController();
  late String _kind = widget.initialKind;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_submitting && _name.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(apiProvider)
          .createChannel(name: _name.text.trim(), kind: _kind);
      final store = await ref.read(storeProvider.future);
      await store.upsertChannels([created]);
      if (!mounted) return;
      final router = GoRouter.of(context);
      Navigator.of(context).pop();
      router.go(Routes.channel(created.id));
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s16,
        0,
        AppSpacing.s16,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.s16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a channel',
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            AppInput(
              controller: _name,
              placeholder: 'Channel name',
              autofocus: true,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_canSubmit) _submit();
              },
              semanticLabel: 'Channel name',
            ),
            const SizedBox(height: AppSpacing.s12),
            AppSegmentedControl.inline(
              semanticLabel: 'Channel kind',
              options: const [
                AppSegmentedOption(label: 'Text'),
                AppSegmentedOption(label: 'Voice'),
              ],
              selectedIndex: _kind == 'voice' ? 1 : 0,
              onSegmentSelected: (i) =>
                  setState(() => _kind = i == 1 ? 'voice' : 'text'),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(
                _error!,
                style: AppText.caption.copyWith(color: tokens.dangerText),
              ),
            ],
            const SizedBox(height: AppSpacing.s12),
            AppButton(
              label: _submitting ? 'Creating...' : 'Create channel',
              variant: AppButtonVariant.primary,
              full: true,
              disabled: !_canSubmit,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
