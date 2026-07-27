// SPDX-License-Identifier: Apache-2.0
/// The composer's smaller pieces: the text field itself, a staged
/// attachment's removable chip, and the "who is typing" line that fills its
/// reserved hint-row slot.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/typing_controller.dart';
import 'member_pane.dart';

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
      // Shift+Enter does not match this activator (modifier flags default to
      // "must be unpressed"), so it falls through to the field's newline.
      bindings: {
        if (!soft)
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
Future<void> showComposerActionsSheet(
  BuildContext context, {
  required VoidCallback onAttach,
  required VoidCallback onPoll,
  required VoidCallback onCode,
}) {
  final tokens = Theme.of(context).extension<AppTokens>()!;
  final actions = <(IconData, String, VoidCallback)>[
    (AppIcons.add, 'Attach a file', onAttach),
    (AppIcons.poll, 'Create a poll', onPoll),
    (AppIcons.code, 'Insert code', onCode),
  ];

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
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

/// Who is typing in this channel, from real `typing.started`/`typing.stopped`
/// events. Receive-only: see `providers/typing_controller.dart` for why this
/// client has nothing to send one back with yet.
class TypingIndicator extends ConsumerWidget {
  const TypingIndicator({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typingIds = ref.watch(typingControllerProvider(channelId));
    if (typingIds.isEmpty) return const SizedBox.shrink();

    final tokens = Theme.of(context).extension<AppTokens>()!;
    final members =
        ref.watch(membersProvider).valueOrNull ?? const <api.UserProfile>[];
    String nameFor(String id) => members
        .firstWhere(
          (m) => m.id == id,
          orElse: () => api.UserProfile(
            id: id,
            username: id,
            displayName: 'Someone',
            createdAt: 0,
          ),
        )
        .displayName;

    final names = typingIds.map(nameFor).toList()..sort();
    final label = names.length == 1
        ? '${names.first} is typing…'
        : '${names.join(', ')} are typing…';

    return Text(
      label,
      style: AppText.code.copyWith(color: tokens.textSecondary),
    );
  }
}
