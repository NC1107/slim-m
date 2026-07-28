// SPDX-License-Identifier: Apache-2.0
/// The message composer: a bordered card, its affordances, and the hint row
/// beneath it.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../providers/typing_controller.dart';
import 'composer_extras.dart';
import 'emoji_picker.dart';
import 'poll_composer_sheet.dart';

class Composer extends ConsumerStatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.channelId,
    required this.channelName,
    required this.onSend,
  });

  final TextEditingController controller;
  final String channelId;
  final String channelName;

  /// Sends the composed text plus whatever attachments were staged before
  /// the send. Ids are already-uploaded attachment ids (see
  /// [SlimmApiAttachments.uploadAttachment]); staging happens here so the
  /// upload finishes before the send request ever goes out.
  final Future<void> Function(List<String> attachmentIds) onSend;

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  /// Two flags, one purpose each. [_hasText] drives the placeholder and is
  /// deliberately untrimmed, so typed spaces hide it; [_hasSendableText] is
  /// trimmed, because the send path drops whitespace-only text.
  bool _hasText = false;
  bool _hasSendableText = false;
  bool _uploading = false;
  final List<api.Attachment> _pendingAttachments = [];
  final FocusNode _focus = FocusNode();

  /// A staged file is sendable on its own: a photo needs no caption, and the
  /// server accepts an empty body precisely when attachments ride along.
  bool get _canSend => _hasSendableText || _pendingAttachments.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    _hasSendableText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_handleChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    _focus.dispose();
    super.dispose();
  }

  void _handleChange() {
    final hasText = widget.controller.text.isNotEmpty;
    final sendable = widget.controller.text.trim().isNotEmpty;
    if (hasText == _hasText && sendable == _hasSendableText) return;
    setState(() {
      _hasText = hasText;
      _hasSendableText = sendable;
    });
  }

  /// Replaces the current selection (or inserts at the caret) and leaves the
  /// caret [caretOffset] characters after the start of what was inserted.
  void _insert(String text, {int? caretOffset}) {
    final controller = widget.controller;
    final selection = controller.selection;
    final value = controller.text;
    final start = selection.start < 0 ? value.length : selection.start;
    final end = selection.end < 0 ? value.length : selection.end;
    controller.value = TextEditingValue(
      text: value.replaceRange(start, end, text),
      selection: TextSelection.collapsed(
        offset: start + (caretOffset ?? text.length),
      ),
    );
  }

  void _insertCodeFence() => _insert('``', caretOffset: 1);

  /// The Space's own emoji only. Native ones come from the keyboard already
  /// under the field, which searches and skin-tones better than this could.
  void _pickEmoji() => unawaited(
    showSpaceEmojiSheet(
      context,
      onSelect: (emoji) {
        _focus.requestFocus();
        _insert(emoji);
      },
    ),
  );

  void _openActions() => unawaited(
    showComposerActionsSheet(
      context,
      onAttach: () => unawaited(_pickAttachment()),
      onPoll: () => showPollComposerSheet(context, widget.channelId),
      onCode: _insertCodeFence,
    ),
  );

  /// Re-focuses first so a soft keyboard stays up across the send, matching
  /// what the field's own submit action does.
  void _sendFromButton() {
    _focus.requestFocus();
    unawaited(_send());
  }

  /// Re-focuses the field on every exit, including a cancelled pick: the
  /// native picker takes focus with it, and without this the caret never
  /// comes back and typing goes nowhere.
  Future<void> _pickAttachment() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles();
    } catch (e) {
      if (!mounted) return;
      _focus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the file picker. $e')),
      );
      return;
    }
    if (!mounted) return;
    _focus.requestFocus();
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final file = files.first;

    setState(() => _uploading = true);
    try {
      // readAsBytes streams from disk; file_picker 12 deprecated withData and
      // PlatformFile.bytes because eager loading OOMs on a large pick.
      final bytes = await file.readAsBytes();
      final attachment = await ref
          .read(apiProvider)
          .uploadAttachment(bytes, filename: file.name);
      if (!mounted) return;
      setState(() {
        _pendingAttachments.add(attachment);
        _uploading = false;
      });
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not attach the file. ${e.message}')),
      );
    }
  }

  void _removeAttachment(api.Attachment attachment) {
    setState(() => _pendingAttachments.remove(attachment));
  }

  void _onTyping(String _) => ref
      .read(typingControllerProvider(widget.channelId).notifier)
      .notifyTyping();

  Future<void> _send() async {
    final ids = _pendingAttachments.map((a) => a.id).toList(growable: false);
    await widget.onSend(ids);
    if (mounted) setState(() => _pendingAttachments.clear());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final touch = AppTouchTargets.of(context);

    // top: false because the composer only ever touches the bottom edge; the
    // padding self-cancels when the keyboard covers the home indicator.
    return SafeArea(
      top: false,
      child: Padding(
        // The same gutter the message rows and the header use; a composer
        // inset differently from the messages above it is visibly crooked.
        padding: EdgeInsets.fromLTRB(
          touch ? AppSizes.paneGutterCompact : AppSizes.paneGutter,
          0,
          touch ? AppSizes.paneGutterCompact : AppSizes.paneGutter,
          8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pendingAttachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                child: Wrap(
                  spacing: AppSpacing.s8,
                  runSpacing: AppSpacing.s8,
                  children: [
                    for (final attachment in _pendingAttachments)
                      StagedAttachmentChip(
                        filename: attachment.filename,
                        onRemove: () => _removeAttachment(attachment),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: TypingIndicator(channelId: widget.channelId),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 5, 10, 5),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                border: Border.all(color: tokens.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AppIconButton(
                    icon: AppIcons.add,
                    semanticLabel: touch ? 'More actions' : 'Attach a file',
                    tooltip: _uploading
                        ? 'Uploading...'
                        : (touch ? 'More actions' : 'Attach a file'),
                    onPressed: _uploading
                        ? null
                        : (touch ? _openActions : _pickAttachment),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  Expanded(
                    child: ComposerField(
                      controller: widget.controller,
                      focusNode: _focus,
                      channelName: widget.channelName,
                      hasText: _hasText,
                      onSend: _send,
                      onTyping: _onTyping,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s8),
                  // Behind the add button at touch density, where the row has
                  // no room for them; see [showComposerActionsSheet].
                  if (!touch) ...[
                    AppIconButton(
                      icon: AppIcons.poll,
                      semanticLabel: 'Create a poll',
                      tooltip: 'Create a poll',
                      onPressed: () =>
                          showPollComposerSheet(context, widget.channelId),
                    ),
                    AppIconButton(
                      icon: AppIcons.code,
                      semanticLabel: 'Insert code',
                      tooltip: 'Insert code',
                      onPressed: _insertCodeFence,
                    ),
                  ],
                  AppIconButton(
                    icon: AppIcons.smile,
                    semanticLabel: 'Insert emoji',
                    tooltip: 'Insert emoji',
                    onPressed: _pickEmoji,
                  ),
                  // Always rendered, only disabled when empty: revealing it on
                  // the first keystroke would reflow the field.
                  AppIconButton(
                    icon: AppIcons.send,
                    semanticLabel: 'Send message',
                    tooltip: 'Send message',
                    onPressed: _canSend ? _sendFromButton : null,
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: NewlineHint(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
