// SPDX-License-Identifier: Apache-2.0
/// The sheet the composer's poll button opens: a question and 2-4 options,
/// sent through `POST /channels/{id}/messages/polls`
/// ([api.SlimmApiMessages.sendPollMessage]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../ids.dart';
import '../providers/message_extras.dart';
import '../providers/providers.dart';

Future<void> showPollComposerSheet(BuildContext context, String channelId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _PollComposerSheet(channelId: channelId),
  );
}

class _PollComposerSheet extends ConsumerStatefulWidget {
  const _PollComposerSheet({required this.channelId});

  final String channelId;

  @override
  ConsumerState<_PollComposerSheet> createState() => _PollComposerSheetState();
}

class _PollComposerSheetState extends ConsumerState<_PollComposerSheet> {
  final _question = TextEditingController();

  /// Four fields shown up front rather than a dynamic add/remove list: the
  /// endpoint accepts 2-4 options, and this way the sheet needs no "remove
  /// option" affordance (there is no icon in this system's vocabulary for
  /// one) - the last two fields simply stay optional.
  final _options = List.generate(4, (_) => TextEditingController());

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    for (final controller in _options) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> get _filledOptions =>
      _options.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();

  bool get _canSubmit =>
      !_submitting &&
      _question.text.trim().isNotEmpty &&
      _filledOptions.length >= 2;

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final sent = await ref
          .read(apiProvider)
          .sendPollMessage(
            channelId: widget.channelId,
            id: newMessageId(),
            question: _question.text.trim(),
            options: _filledOptions,
          );
      final store = await ref.read(storeProvider.future);
      await store.applyMessage(sent);
      ref.read(messageExtrasProvider.notifier).applyMessage(sent);
      if (mounted) Navigator.of(context).pop();
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
              'New poll',
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            AppInput(
              controller: _question,
              placeholder: 'Ask a question',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.s8),
            for (var i = 0; i < _options.length; i++) ...[
              AppInput(
                controller: _options[i],
                placeholder: 'Option ${i + 1}${i < 2 ? '' : ' (optional)'}',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            if (_error != null) ...[
              Text(
                _error!,
                style: AppText.caption.copyWith(color: tokens.dangerText),
              ),
              const SizedBox(height: AppSpacing.s8),
            ],
            AppButton(
              label: _submitting ? 'Sending...' : 'Send poll',
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
