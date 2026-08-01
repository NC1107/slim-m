// SPDX-License-Identifier: Apache-2.0
/// The composer's smaller pieces: the text field itself, its markdown key
/// bindings, and a staged attachment's removable chip.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slimm_design_system/design_system.dart';

import 'composer_markdown_shortcuts.dart';

/// Whether this platform's primary text input is a soft keyboard, which has
/// no shift key and turns the return key into whatever `textInputAction`
/// asks for.
///
/// Read from the theme rather than `Platform.isX` so a test can override it,
/// and deliberately not from `LayoutClass`: a narrow desktop window is
/// compact but still has a real Enter key. This is input modality, not
/// layout.
bool usesSoftKeyboard(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.iOS ||
      TargetPlatform.android ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };

/// The composer's text entry: the placeholder, the field, and the one way a
/// return key reaches [onSend] on each platform.
///
/// On a soft keyboard the field asks the engine for a send action, because a
/// raw Enter key event only exists on hardware keyboards. On desktop the
/// action stays null, which leaves the engine inserting newlines and lets
/// [CallbackShortcuts] own plain Enter, so Shift+Enter still falls through.
///
/// Exactly one of those is live at a time. An iPad with a hardware keyboard
/// is a soft-keyboard platform holding a real Enter key, so both would fire
/// for one press, and the send would go out twice.
class ComposerField extends StatelessWidget {
  const ComposerField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.channelName,
    required this.hasText,
    required this.onSend,
    required this.onTyping,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String channelName;
  final bool hasText;
  final Future<void> Function() onSend;
  final ValueChanged<String> onTyping;

  /// Re-focusing before sending is what keeps the soft keyboard up:
  /// `_finalizeEditing` has already unfocused, and only re-opens the input
  /// connection if the callback focuses the field again.
  void _submit() {
    focusNode.requestFocus();
    unawaited(onSend());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final soft = usesSoftKeyboard(context);

    return CallbackShortcuts(
      bindings: {
        if (!soft)
          const SingleActivator(LogicalKeyboardKey.enter): () => onSend(),
        // Shift+Enter is a hardware-only combination, hence gated the same
        // as plain Enter above; it used to fall through to the field's own
        // newline untouched, which a list continuation now has to pre-empt.
        if (!soft)
          const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
              controller.value = applyListAwareEnter(controller.value),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            controller.value = wrapSelectionWithMarker(controller.value, '**'),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            controller.value = wrapSelectionWithMarker(controller.value, '**'),
        const SingleActivator(LogicalKeyboardKey.keyI, control: true): () =>
            controller.value = wrapSelectionWithMarker(controller.value, '*'),
        const SingleActivator(LogicalKeyboardKey.keyI, meta: true): () =>
            controller.value = wrapSelectionWithMarker(controller.value, '*'),
      },
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (!hasText)
            IgnorePointer(
              child: Text.rich(
                TextSpan(
                  // textSecondary, matching AppInput's hint: this input is
                  // active, and textDisabled's AA exemption does not apply.
                  style: AppText.body.copyWith(color: tokens.textSecondary),
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
            focusNode: focusNode,
            onChanged: onTyping,
            minLines: 1,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textInputAction: soft ? TextInputAction.send : null,
            onSubmitted: soft ? (_) => _submit() : null,
            style: AppText.body.copyWith(color: tokens.textPrimary),
            cursorColor: tokens.accent,
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              // Opts out of the global boxed-input theme; the surrounding
              // widget draws its own chrome.
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

/// One attachment uploaded but not yet sent. The whole chip is the tap
/// target for removing it, since [AppChip.operator] is deliberately
/// non-interactive and there is no dedicated "remove" glyph in
/// [AppIcons] to reach for instead.
class StagedAttachmentChip extends StatelessWidget {
  const StagedAttachmentChip({
    super.key,
    required this.filename,
    required this.onRemove,
  });

  final String filename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      label: 'Remove attachment $filename',
      button: true,
      child: GestureDetector(
        onTap: onRemove,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            border: Border.all(color: tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                filename,
                style: AppText.caption.copyWith(color: tokens.textPrimary),
              ),
              const SizedBox(width: AppSpacing.s4),
              Text(
                'x',
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The composer's secondary actions, off the row rather than on it.
///
/// At touch density five 44pt controls plus their gaps leave a 390pt phone
/// about 90pt of text field, measured, which is not a composer any longer.
/// Attach, poll and code move behind the one button that already means "add
/// something"; emoji and send stay on the row because both are used mid-
/// sentence, where a sheet would cost the caret.
///
/// Attaching splits into two rows rather than one, because a single "Attach
/// a file" hid a choice `file_picker` actually requires on iOS and Android;
/// see `attachment_picker.dart` for why the two cannot share one request.
Future<void> showComposerActionsSheet(
  BuildContext context, {
  required VoidCallback onPhotoLibrary,
  required VoidCallback onBrowseFiles,
  required VoidCallback onPoll,
  required VoidCallback onCode,
}) {
  final tokens = Theme.of(context).extension<AppTokens>()!;
  final actions = <(IconData, String, VoidCallback)>[
    (AppIcons.image, 'Photo library', onPhotoLibrary),
    (AppIcons.attachFile, 'Browse files', onBrowseFiles),
    (AppIcons.poll, 'Create a poll', onPoll),
    (AppIcons.code, 'Insert code', onCode),
  ];

  return showAppSheet<void>(
    context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.s12,
          0,
          AppSpacing.s12,
          AppSpacing.s12,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (icon, label, action) in actions)
              AppListRow(
                label: label,
                leading: Icon(
                  icon,
                  size: AppSizes.icon16,
                  color: tokens.textSecondary,
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  action();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// The "shift + enter for newline" hint, shown only where a hardware Enter
/// key exists.
///
/// Kept in the tree at full size while hidden so the composer does not jump,
/// and `maintainSemantics` is left at its false default so a screen reader
/// never announces a key the device has not got. The caller wraps this in a
/// [Flexible] because the reserved space is a height, not a width: at full
/// width the line overflows a 390pt phone by 9pt.
class NewlineHint extends StatelessWidget {
  const NewlineHint({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Visibility(
      key: const Key('composer-newline-hint'),
      // No maintainSize: it is the only thing on its row now that the typing
      // indicator sits above the card, so reserving its height on a phone,
      // where it is never shown, is pure wasted space.
      visible: !usesSoftKeyboard(context),
      child: Text(
        'shift + enter for newline',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: AppText.code.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}
