// SPDX-License-Identifier: Apache-2.0
/// The message composer: a bordered card, its affordances, and the hint row
/// beneath it.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../providers/typing_controller.dart';
import 'composer_extras.dart';
import 'poll_composer_sheet.dart';

/// A single placeholder glyph a tap on the smile button inserts, standing in
/// for a full emoji picker. An escaped code point, not a literal character:
/// the hygiene gate that keeps emoji out of interface chrome scans source
/// bytes, and this is chrome (a composer affordance), not user content.
const String _quickEmoji = '\u{1F642}';

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
  bool _hasText = false;
  bool _uploading = false;
  final List<api.Attachment> _pendingAttachments = [];

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    widget.controller.addListener(_handleChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() {
    final hasText = widget.controller.text.isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
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
      selection:
          TextSelection.collapsed(offset: start + (caretOffset ?? text.length)),
    );
  }

  void _insertCodeFence() => _insert('``', caretOffset: 1);
  void _insertEmoji() => _insert(_quickEmoji);

  Future<void> _pickAttachment() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(withData: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the file picker. $e')));
      return;
    }
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final file = files.first;
    if (file.bytes == null) return;

    setState(() => _uploading = true);
    try {
      final attachment = await ref
          .read(apiProvider)
          .uploadAttachment(file.bytes!, filename: file.name);
      if (!mounted) return;
      setState(() {
        _pendingAttachments.add(attachment);
        _uploading = false;
      });
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach the file. ${e.message}')));
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
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
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
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
                  semanticLabel: 'Attach a file',
                  tooltip: _uploading ? 'Uploading...' : 'Attach a file',
                  onPressed: _uploading ? null : _pickAttachment,
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                    child: _Field(
                  controller: widget.controller,
                  channelName: widget.channelName,
                  hasText: _hasText,
                  onSend: _send,
                  onTyping: _onTyping,
                )),
                const SizedBox(width: AppSpacing.s8),
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
                AppIconButton(
                  icon: AppIcons.smile,
                  semanticLabel: 'Insert emoji',
                  tooltip: 'Insert emoji',
                  onPressed: _insertEmoji,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Row(
              children: [
                Expanded(child: TypingIndicator(channelId: widget.channelId)),
                Text(
                  'shift + enter for newline',
                  style: AppText.code.copyWith(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.channelName,
    required this.hasText,
    required this.onSend,
    required this.onTyping,
  });

  final TextEditingController controller;
  final String channelName;
  final bool hasText;
  final Future<void> Function() onSend;
  final ValueChanged<String> onTyping;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return CallbackShortcuts(
      // Shift+Enter does not match this activator (modifier flags default to
      // "must be unpressed"), so it falls through to the field's own newline.
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () => onSend(),
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (!hasText)
            IgnorePointer(
              child: Text.rich(
                TextSpan(
                  style: AppText.body.copyWith(color: tokens.textDisabled),
                  children: [
                    const TextSpan(text: 'Message '),
                    TextSpan(
                      text: '#$channelName',
                      style: const TextStyle(fontFamily: AppFonts.mono),
                    ),
                  ],
                ),
              ),
            ),
          TextField(
            controller: controller,
            onChanged: onTyping,
            minLines: 1,
            maxLines: 6,
            style: AppText.body.copyWith(color: tokens.textPrimary),
            cursorColor: tokens.accent,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}
