// SPDX-License-Identifier: Apache-2.0
/// The message composer: a bordered card, its affordances, and the hint row
/// beneath it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Unaliased: `uploadAttachment` is an extension method, visible only where imported.
import 'package:slimm_api/api.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/admin_providers.dart';
import '../providers/composer_focus.dart';
import '../providers/member_presence.dart' show membersProvider;
import '../providers/providers.dart';
import '../providers/typing_controller.dart';
import 'attachment_picker.dart';
import 'composer_action_bar.dart';
import 'composer_attachments.dart';
import 'composer_autocomplete.dart';
import 'composer_autocomplete_items.dart';
import 'composer_autocomplete_query.dart';
import 'composer_clipboard_image.dart';
import 'composer_clipboard_paste.dart';
import 'composer_extras.dart';
import 'emoji_picker.dart';
import 'poll_composer_sheet.dart';
import 'typing_indicator.dart';

class Composer extends ConsumerStatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.channelId,
    required this.channelName,
    required this.onSend,
    this.clipboardPasteStart = startClipboardImagePaste,
    this.clipboardPasteStop = stopClipboardImagePaste,
  });

  final TextEditingController controller;
  final String channelId;
  final String channelName;

  /// Sends the composed text plus whatever attachments were staged before
  /// the send. Ids are already-uploaded attachment ids (see
  /// `SlimmApiAttachments.uploadAttachment`); staging happens here so the
  /// upload finishes before the send request ever goes out.
  /// The send button is disabled while anything staged has not resolved to
  /// an id yet, so this never receives fewer ids than what is visibly
  /// attached.
  final Future<void> Function(List<String> attachmentIds) onSend;

  /// The Ctrl+V seam (see `composer_clipboard_image.dart`): real on web, a
  /// no-op everywhere else. Parameters rather than a direct call so a test
  /// can hand over a fake that fires synchronously, since nothing about a
  /// real browser paste event can be produced from a widget test.
  final void Function(PastedImageHandler onImage) clipboardPasteStart;

  /// Takes the same callback [clipboardPasteStart] was given, which is also
  /// the ownership token that stops this from tearing down a *different*
  /// caller's still-active registration - see the web implementation's own
  /// doc for the race this closes.
  final void Function(PastedImageHandler onImage) clipboardPasteStop;

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  /// Two flags, one purpose each. [_hasText] drives the placeholder and is
  /// deliberately untrimmed, so typed spaces hide it; [_hasSendableText] is
  /// trimmed, because the send path drops whitespace-only text.
  bool _hasText = false;
  bool _hasSendableText = false;
  late final AttachmentStagingController _attachments;

  /// Shown inline above the action bar: a picker that would not open, or a
  /// clipboard paste that failed. Both are "could not get you an
  /// attachment", the one band `ComposerBanners` reserves for it.
  String? _attachmentError;
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);

  /// The composed text's own length and how far over [kMessageMaxChars] it
  /// sits, if at all. Tracked alongside [_hasText] rather than read fresh in
  /// [build], so [_handleChange] can decide when a rebuild is worth it.
  int _charCount = 0;
  int? _overBy;

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
  /// Blocked while anything staged is still uploading or has failed, or a
  /// send would go out missing whatever has not resolved to an id yet.
  /// Also blocked over the character limit, so a doomed request never
  /// reaches the wire at all; see [ComposerBanners]'s `overLimitBy` band for
  /// where that refusal is explained.
  bool get _canSend =>
      (_hasSendableText || !_attachments.isEmpty) &&
      !_attachments.hasBlockingAttachment &&
      _overBy == null;

  @override
  void initState() {
    super.initState();
    _attachments = AttachmentStagingController(
      upload: (bytes, filename) =>
          ref.read(apiProvider).uploadAttachment(bytes, filename: filename),
    )..addListener(_handleAttachmentsChange);
    _hasText = widget.controller.text.isNotEmpty;
    _hasSendableText = widget.controller.text.trim().isNotEmpty;
    _charCount = widget.controller.text.runes.length;
    _overBy = messageLengthOverage(_charCount);
    widget.controller.addListener(_handleChange);
    _focus.addListener(_handleFocusChange);
    // See [_focusRegistry]'s doc comment for why this waits a frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final registry = ref.read(composerFocusNodeProvider.notifier);
      registry.state = _focus;
      _focusRegistry = registry;
    });
  }

  @override
  void didUpdateWidget(covariant Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // See [AttachmentStagingController.resetForChannelSwitch]'s own doc comment.
    if (oldWidget.channelId != widget.channelId) {
      _attachments.resetForChannelSwitch();
      if (mounted) setState(() => _attachmentError = null);
    }
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
    _focus.removeListener(_handleFocusChange);
    widget.clipboardPasteStop(_handlePastedImage);
    _focus.dispose();
    _attachments.removeListener(_handleAttachmentsChange);
    _attachments.dispose();
    super.dispose();
  }

  /// Every staging change (a pick appearing, an upload settling, a retry or
  /// a removal) rebuilds through here rather than a `setState` at each call
  /// site, so a state the controller reaches on its own (an upload finally
  /// resolving) repaints exactly like one a tap caused directly.
  void _handleAttachmentsChange() {
    if (mounted) setState(() {});
  }

  /// Ctrl+V only reaches an image while this field genuinely has focus: the
  /// seam behind [Composer.clipboardPasteStart] is a single global listener
  /// (see `composer_clipboard_image_web.dart`), so it has to be handed off
  /// on every focus change rather than left running for the widget's whole
  /// life.
  void _handleFocusChange() {
    if (_focus.hasFocus) {
      widget.clipboardPasteStart(_handlePastedImage);
    } else {
      widget.clipboardPasteStop(_handlePastedImage);
    }
  }

  void _handleChange() {
    final hasText = widget.controller.text.isNotEmpty;
    final sendable = widget.controller.text.trim().isNotEmpty;
    final charCount = widget.controller.text.runes.length;
    final overBy = messageLengthOverage(charCount);
    final query = autocompleteQueryAt(
      widget.controller.text,
      widget.controller.selection.baseOffset,
    );
    // True while the counter is or was on screen, so its own value keeps redrawing.
    final countMatters =
        messageCounterVisible(charCount) || messageCounterVisible(_charCount);
    final changed =
        hasText != _hasText ||
        sendable != _hasSendableText ||
        query != _query ||
        overBy != _overBy ||
        (countMatters && charCount != _charCount);
    if (!changed) return;
    setState(() {
      _hasText = hasText;
      _hasSendableText = sendable;
      _charCount = charCount;
      _overBy = overBy;
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
  ///
  /// The paste check sits above the autocomplete guard on purpose, since it
  /// has to run whether or not a mention list happens to be open, and it
  /// never returns `handled`, so Flutter's own text paste is untouched.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (isClipboardPasteChord(event)) {
      unawaited(
        pasteClipboardImageFromKeystroke(_stageAttachment, _setAttachmentError),
      );
    }
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
      final keyboard = HardwareKeyboard.instance;
      // A held modifier is a global shortcut (Ctrl/Cmd+Tab cycles channels), not an accept.
      if (keyboard.isShiftPressed ||
          keyboard.isControlPressed ||
          keyboard.isMetaPressed) {
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
      onPhotoLibrary: () =>
          unawaited(_pickAttachment(AttachmentSource.photoLibrary)),
      onBrowseFiles: () =>
          unawaited(_pickAttachment(AttachmentSource.fileBrowser)),
      canPasteImage: composerClipboardPasteAvailable(),
      onPasteImage: () =>
          unawaited(pasteClipboardImage(_stageAttachment, _setAttachmentError)),
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

  /// Desktop has no photo-versus-files split (see `attachment_picker.dart`),
  /// so its single tap goes straight to the document picker.
  void _pickFileFromButton() =>
      unawaited(_pickAttachment(AttachmentSource.fileBrowser));

  /// Cleared up front, the same precedent `pasteClipboardImage`'s own doc
  /// comment names: a retry that succeeds must not leave a stale failure on
  /// screen above the attachment it just staged.
  Future<void> _pickAttachment(AttachmentSource source) {
    _setAttachmentError(null);
    return runAttachmentPick(
      pick: ref.read(attachmentPickerProvider(source)),
      focus: _focus,
      isMounted: () => mounted,
      onPickerFailed: () =>
          _setAttachmentError('Could not open the file picker.'),
      stage: _stageAttachment,
    );
  }

  /// Stages bytes from wherever they came from: visible immediately (see
  /// [AttachmentStagingController.stage]), with the upload itself running in
  /// the background. Shared by the file picker and a pasted image so
  /// neither invents its own way onto the send path.
  Future<void> _stageAttachment(Uint8List bytes, String filename) =>
      _attachments.stage(bytes, filename);

  /// Handed to [Composer.clipboardPasteStart] as the callback a pasted
  /// image reaches; it goes through the exact same staging path a picked
  /// file does, never a second attachment mechanism.
  void _handlePastedImage(Uint8List bytes, String filename) =>
      unawaited(_stageAttachment(bytes, filename));

  void _setAttachmentError(String? message) {
    if (mounted) setState(() => _attachmentError = message);
  }

  void _removeAttachment(String localId) => _attachments.remove(localId);

  void _retryAttachment(String localId) => _attachments.retry(localId);

  void _onTyping(String _) => ref
      .read(typingControllerProvider(widget.channelId).notifier)
      .notifyTyping();

  Future<void> _send() async {
    final ids = _attachments.readyIds;
    await widget.onSend(ids);
    if (mounted) _attachments.clear();
  }

  @override
  Widget build(BuildContext context) {
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
            ComposerBanners(
              attachmentError: _attachmentError,
              onDismissAttachmentError: () =>
                  setState(() => _attachmentError = null),
              overLimitBy: _overBy,
              stagedAttachments: _attachments.items,
              onRemoveAttachment: _removeAttachment,
              onRetryAttachment: _retryAttachment,
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
            ComposerActionBar(
              touch: touch,
              controller: widget.controller,
              focusNode: _focus,
              channelId: widget.channelId,
              channelName: widget.channelName,
              hasText: _hasText,
              canSend: _canSend,
              onSend: _send,
              onTyping: _onTyping,
              onOpenActions: _openActions,
              onPickFile: _pickFileFromButton,
              onSendPressed: _sendFromButton,
              onInsertCode: _insertCodeFence,
              onPickEmoji: _pickEmoji,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: MessageLengthCounter(length: _charCount),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
