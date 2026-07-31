// SPDX-License-Identifier: Apache-2.0
/// The message composer: a bordered card, its affordances, and the hint row
/// beneath it.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../providers/admin_providers.dart';
import '../providers/composer_focus.dart';
import '../providers/member_presence.dart' show membersProvider;
import '../providers/providers.dart';
import '../providers/typing_controller.dart';
import 'composer_autocomplete.dart';
import 'composer_autocomplete_items.dart';
import 'composer_autocomplete_query.dart';
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
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);

  /// Captured once rather than read from `ref` in [dispose]: by then
  /// Riverpod has already detached this element's `ref`, and reading it
  /// throws "Cannot use ref after the widget was disposed". Every write to
  /// it, from [initState] and [dispose] alike, goes through a post-frame
  /// callback rather than running synchronously: either method can be
  /// reached as part of the very build/frame that swaps this widget out
  /// (for `BlockedDmNotice` among others), and a provider write from there
  /// is a build-time mutation, which Riverpod rejects outside tests too.
  StateController<FocusNode?>? _focusRegistry;

  /// The trigger the caret is inside, and which of its offers is current.
  ///
  /// Held here rather than in the panel because all three act on the text
  /// field this widget owns: the keys are intercepted on its focus node, and
  /// accepting rewrites its value.
  AutocompleteQuery? _query;
  List<AutocompleteSuggestion> _suggestions = const [];
  int _selected = 0;

  /// A staged file is sendable on its own: a photo needs no caption, and the
  /// server accepts an empty body precisely when attachments ride along.
  bool get _canSend => _hasSendableText || _pendingAttachments.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _hasText = widget.controller.text.isNotEmpty;
    _hasSendableText = widget.controller.text.trim().isNotEmpty;
    widget.controller.addListener(_handleChange);
    // See [_focusRegistry]'s doc comment for why this waits a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final registry = ref.read(composerFocusNodeProvider.notifier);
      registry.state = _focus;
      _focusRegistry = registry;
    });
  }

  @override
  void dispose() {
    // Guards mounted too: the whole container can be gone by this frame.
    final registry = _focusRegistry;
    final focus = _focus;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (registry != null && registry.mounted && registry.state == focus) {
        registry.state = null;
      }
    });
    widget.controller.removeListener(_handleChange);
    _focus.dispose();
    super.dispose();
  }

  void _handleChange() {
    final hasText = widget.controller.text.isNotEmpty;
    final sendable = widget.controller.text.trim().isNotEmpty;
    final query = autocompleteQueryAt(
      widget.controller.text,
      widget.controller.selection.baseOffset,
    );
    final changed =
        hasText != _hasText || sendable != _hasSendableText || query != _query;
    if (!changed) return;
    setState(() {
      _hasText = hasText;
      _hasSendableText = sendable;
      if (query != _query) {
        _query = query;
        // Back to row one, so Enter takes whatever now ranks first.
        _selected = 0;
      }
    });
  }

  /// Rebuilt during build rather than stored, since the member list and the
  /// Space's emoji are both watched providers and either can arrive late.
  List<AutocompleteSuggestion> _buildSuggestions() {
    final query = _query;
    if (query == null) return const [];
    return autocompleteSuggestions(
      query: query,
      custom: ref.watch(customEmojiProvider).valueOrNull ?? const [],
      members: ref.watch(membersProvider).valueOrNull ?? const [],
      selfId: ref.watch(meProvider).valueOrNull?.id,
    );
  }

  void _dismissAutocomplete() {
    if (_query == null) return;
    setState(() {
      _query = null;
      _selected = 0;
    });
  }

  /// Replaces the trigger span with what was chosen and closes the list.
  void _accept(AutocompleteSuggestion suggestion) {
    final query = _query;
    if (query == null) return;
    final text = widget.controller.text;
    widget.controller.value = TextEditingValue(
      text: text.replaceRange(query.start, query.end, suggestion.insert),
      selection: TextSelection.collapsed(
        offset: query.start + suggestion.insert.length,
      ),
    );
    _focus.requestFocus();
    _dismissAutocomplete();
  }

  /// Intercepts the keys the list needs, on the field's own focus node.
  ///
  /// It has to be this node rather than an ancestor: text editing handles the
  /// arrows through `Actions` installed above the field, so a handler higher
  /// up would run after the caret had already moved.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_query == null || _suggestions.isEmpty) return KeyEventResult.ignored;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      _dismissAutocomplete();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (_selected + 1) % _suggestions.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _selected =
            (_selected - 1 + _suggestions.length) % _suggestions.length,
      );
      return KeyEventResult.handled;
    }
    // Both accept; Enter would otherwise send the half-typed trigger.
    if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        return KeyEventResult.ignored;
      }
      _accept(_suggestions[_selected]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
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
        const SnackBar(content: Text('Could not open the file picker.')),
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
        SnackBar(content: Text(describeApiFailure('attach the file', e))),
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
    // In build because both sources are watched and can arrive late.
    _suggestions = _buildSuggestions();

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
            // Above the field, never below: that is the send row and keyboard.
            ComposerAutocomplete(
              suggestions: _suggestions,
              selected: _selected,
              onPick: _accept,
              onHover: (i) => setState(() => _selected = i),
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
