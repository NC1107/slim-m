// SPDX-License-Identifier: Apache-2.0
/// The sheet a channel row's manage button opens: rename, set or clear the
/// topic, and delete. `PATCH`/`DELETE /channels/{id}`
/// ([api.SlimmApiChannelAdmin]).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';
import 'channel_rail.dart' show channelIdInPath;
import 'confirm_dialog.dart';

/// Matches the server's own ceiling (`CHANNEL_TOPIC_MAX_CHARS` in
/// `crates/slimm-server/src/http/channels.rs`), so the counter here never
/// disagrees with the length check the request will actually be judged
/// against.
const int _topicMaxChars = 256;
const int _nameMaxChars = 64;

Future<void> showManageChannelSheet(BuildContext context, Channel channel) {
  return showAppSheet<void>(
    context,
    builder: (context) => _ManageChannelSheet(channel: channel),
  );
}

class _ManageChannelSheet extends ConsumerStatefulWidget {
  const _ManageChannelSheet({required this.channel});

  final Channel channel;

  @override
  ConsumerState<_ManageChannelSheet> createState() =>
      _ManageChannelSheetState();
}

class _ManageChannelSheetState extends ConsumerState<_ManageChannelSheet> {
  late final _name = TextEditingController(text: widget.channel.name);
  late final _topic = TextEditingController(text: widget.channel.topic ?? '');
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _topic.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _name.text.trim() != widget.channel.name ||
      _topic.text.trim() != (widget.channel.topic ?? '');

  bool get _nameValid =>
      _name.text.trim().isNotEmpty && _name.text.trim().length <= _nameMaxChars;

  bool get _topicValid => _topic.text.trim().length <= _topicMaxChars;

  bool get _canSave =>
      !_saving && !_deleting && _dirty && _nameValid && _topicValid;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(apiProvider)
          .updateChannel(
            channelId: widget.channel.id,
            name: _name.text.trim(),
            topic: _topic.text,
          );
      final store = await ref.read(storeProvider.future);
      await store.upsertChannels([updated]);
      if (mounted) Navigator.of(context).pop();
    } on api.ApiException catch (e) {
      if (mounted) {
        setState(() => _error = describeApiFailure('save the changes', e));
      }
    } finally {
      // Any escape, not just ApiException, must not wedge "Saving..." on.
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Delete "${widget.channel.name}"?',
      message:
          'This deletes the channel and its message history for everyone '
          'in the Space. This cannot be undone.',
      confirmLabel: 'Delete permanently',
      cancelLabel: 'Keep channel',
    );
    if (confirmed) await _delete();
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    // This sheet is a modal route on the root navigator, so GoRouterState.of
    // would throw here; GoRouter.of resolves through an InheritedWidget.
    final router = GoRouter.of(context);
    final wasOpen = channelIdInPath(router.state.uri.path) == widget.channel.id;
    try {
      await ref.read(apiProvider).deleteChannel(widget.channel.id);
      final store = await ref.read(storeProvider.future);
      await store.removeChannel(widget.channel.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      // Otherwise the pane behind this sheet keeps showing a channel that no
      // longer exists in the local store.
      if (wasOpen) router.go(Routes.channels);
    } on api.ConflictException {
      // The server's wording is accurate but terse, and this feature's own
      // requirement is a full sentence rather than a bare error.
      if (mounted) {
        setState(
          () => _error =
              'This is the last channel here. Create another channel '
              'before deleting this one.',
        );
      }
    } on api.ApiException catch (e) {
      if (mounted) {
        setState(() => _error = describeApiFailure('delete the channel', e));
      }
    } finally {
      // Any escape, not just the two catches, must not wedge "Deleting..." on.
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final topicLength = _topic.text.trim().length;

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
              'Manage channel',
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            AppInput(
              controller: _name,
              placeholder: 'Channel name',
              onChanged: (_) => setState(() {}),
              semanticLabel: 'Channel name',
            ),
            const SizedBox(height: AppSpacing.s8),
            AppInput(
              controller: _topic,
              placeholder: 'Topic - leave blank to clear',
              onChanged: (_) => setState(() {}),
              semanticLabel: 'Channel topic',
            ),
            const SizedBox(height: AppSpacing.s4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$topicLength/$_topicMaxChars',
                style: AppText.micro.copyWith(
                  color: topicLength > _topicMaxChars
                      ? tokens.dangerText
                      : tokens.textSecondary,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s8),
              AppErrorState(message: _error!),
            ],
            const SizedBox(height: AppSpacing.s12),
            AppButton(
              label: _saving ? 'Saving...' : 'Save changes',
              variant: AppButtonVariant.primary,
              full: true,
              disabled: !_canSave,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.s20),
            Container(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'DANGER ZONE',
              style: AppText.label.copyWith(color: tokens.dangerText),
            ),
            const SizedBox(height: AppSpacing.s8),
            AppButton(
              label: _deleting ? 'Deleting...' : 'Delete channel',
              variant: AppButtonVariant.danger,
              full: true,
              disabled: _saving || _deleting,
              onPressed: _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }
}
