// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The inline field a message row swaps in for its rendered body while being
/// edited, in place of a dialog.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slimm_design_system/design_system.dart';

import 'composer_extras.dart' show usesSoftKeyboard;

/// Pre-filled with [initialContent]. Enter saves, Shift+Enter inserts a
/// newline, and Escape cancels on a hardware keyboard, matching the
/// composer's own field.
///
/// Neither key reaches [CallbackShortcuts] from a soft keyboard: a phone's
/// on-screen return key is delivered through the text input channel, never
/// as a raw key event. This field cannot trade Enter for a submit action the
/// way the composer does either, because an edit has to stay multi-line
/// editable on a phone too, so the return key must keep inserting a
/// newline there. Cancel and Save are always drawn below the field instead,
/// which also fixes the row that used to overflow off a phone's width
/// entirely: the hint text plus two `TextButton`s ran past 375 logical
/// pixels, so Save existed in the tree but nowhere a thumb could reach it.
class MessageEditField extends StatefulWidget {
  const MessageEditField({
    super.key,
    required this.initialContent,
    required this.onSubmit,
    required this.onCancel,
  });

  final String initialContent;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<MessageEditField> createState() => _MessageEditFieldState();
}

class _MessageEditFieldState extends State<MessageEditField> {
  late final _controller = TextEditingController(text: widget.initialContent);
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    // An edit down to nothing is a cancel, not a delete: this field has no
    // way to delete the message, so it must leave the original untouched.
    if (text.isEmpty) {
      widget.onCancel();
    } else {
      widget.onSubmit(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // See the class doc: a soft keyboard gets no keyboard-shortcut hint.
    final soft = usesSoftKeyboard(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s8,
          vertical: AppSpacing.s4,
        ),
        decoration: BoxDecoration(
          // The row around it is raised while editing, so the field sits in it as an inset.
          color: tokens.surfaceBase,
          border: Border.all(color: tokens.accentFill),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              minLines: 1,
              maxLines: 10,
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
            const SizedBox(height: AppSpacing.s4),
            _Footer(soft: soft, onCancel: widget.onCancel, onSave: _submit),
          ],
        ),
      ),
    );
  }
}

/// Narrower than this and the hints stack above the buttons: three keycap
/// groups and two buttons need about this much to share a line.
const double _footerSideBySide = 440;

/// The hints and the Cancel and Save buttons, beside each other when they fit
/// and stacked when they do not, so neither is ever cut off.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.soft,
    required this.onCancel,
    required this.onSave,
  });

  final bool soft;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.s8,
      children: [
        AppButton(
          label: 'Cancel',
          variant: AppButtonVariant.ghost,
          size: AppButtonSize.sm,
          onPressed: onCancel,
        ),
        AppButton(
          label: 'Save',
          variant: AppButtonVariant.primary,
          size: AppButtonSize.sm,
          onPressed: onSave,
        ),
      ],
    );
    if (soft) return Align(alignment: Alignment.centerRight, child: buttons);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _footerSideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(child: _KeyHints()),
              buttons,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppSpacing.s8,
          children: [
            const _KeyHints(),
            Align(alignment: Alignment.centerRight, child: buttons),
          ],
        );
      },
    );
  }
}

/// What the keyboard does in the field, as keycaps. Wraps rather than shrinks,
/// so a narrow window gets a second line instead of a cut key.
class _KeyHints extends StatelessWidget {
  const _KeyHints();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: AppSpacing.s12,
      runSpacing: AppSpacing.s4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _KeyHint(keys: ['Esc'], label: 'cancel'),
        _KeyHint(keys: ['Enter'], label: 'save'),
        _KeyHint(keys: ['Shift', 'Enter'], label: 'newline'),
      ],
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint({required this.keys, required this.label});

  final List<String> keys;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final ink = AppText.caption.copyWith(color: tokens.textSecondary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.s4,
      children: [
        for (final (i, key) in keys.indexed) ...[
          if (i > 0) Text('+', style: ink),
          AppKbd(key),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ink,
          ),
        ),
      ],
    );
  }
}
