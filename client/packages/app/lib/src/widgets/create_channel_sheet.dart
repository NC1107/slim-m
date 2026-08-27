// SPDX-License-Identifier: Apache-2.0
/// The sheet the rail's Space menu "Add channel" item opens: a name and a
/// text/voice choice, sent through `POST /channels`
/// ([api.SlimmApi.createChannel]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';

/// The server's own ceiling (`validate_channel_name` in
/// `crates/slimm-server/src/http/channels.rs`), so a name that is already
/// too long is refused here rather than round-tripping to the server first.
const int _nameMaxChars = 64;

/// Opens the sheet, defaulting the kind picker to [initialKind]: still
/// changeable inside the sheet, since it is only a starting guess, not a
/// hard constraint the server enforces.
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

  bool get _nameValid =>
      _name.text.trim().isNotEmpty && _name.text.trim().length <= _nameMaxChars;

  bool get _canSubmit => !_submitting && _nameValid;

  /// Names what is missing rather than sitting disabled with no explanation
  /// - the same "say why" treatment `poll_composer_sheet.dart`'s own button
  /// label gives an incomplete poll.
  String get _buttonLabel {
    if (_submitting) return 'Creating...';
    if (_name.text.trim().isEmpty) return 'Add a channel name';
    if (!_nameValid) return 'Name is too long';
    return 'Create channel';
  }

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
      if (mounted) {
        setState(() => _error = describeApiFailure('create the channel', e));
      }
    } finally {
      // Any escape, not just ApiException, must not wedge "Creating..." on.
      if (mounted) setState(() => _submitting = false);
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
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s16,
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
              AppErrorState(message: _error!),
            ],
            const SizedBox(height: AppSpacing.s12),
            AppButton(
              label: _buttonLabel,
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
