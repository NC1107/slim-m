// SPDX-License-Identifier: Apache-2.0
/// The note tool's own sheet: text entered here, and only here, is what a
/// placed note ever carries.
///
/// There is no in-place edit anywhere on this canvas - a stroke's ink cannot
/// be redrawn, an image's bytes cannot be swapped - so a note follows the
/// same rule and is never edited after placement. That is what makes this
/// sheet the one and only place a note's text is ever typed, and why a note
/// never appears on the shared canvas mid-composition: nothing is sent until
/// this sheet's own submit, so there is nothing for another participant to
/// see somebody "typing into".
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slimm_design_system/design_system.dart';

/// A comfortable margin under the server's `MAX_PROPS_BYTES` (4 KiB): the
/// wire cost is `text` JSON-escaped inside `{"text":"..."}`, and this leaves
/// headroom even for a pathological string of characters that each escape
/// to several bytes.
const int maxNoteTextLength = 1800;

/// Opens the note sheet and answers with the entered text, or null if the
/// person cancelled without typing anything worth keeping.
Future<String?> showCanvasNoteSheet(BuildContext context) {
  return showAppSheet<String?>(
    context,
    builder: (context) => const _CanvasNoteSheet(),
  );
}

class _CanvasNoteSheet extends StatefulWidget {
  const _CanvasNoteSheet();

  @override
  State<_CanvasNoteSheet> createState() => _CanvasNoteSheetState();
}

class _CanvasNoteSheetState extends State<_CanvasNoteSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _canSubmit => _text.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.of(context).pop(_text.text.trim());
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add a note',
            style: AppText.body.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Container(
            decoration: BoxDecoration(
              color: tokens.surfaceBase,
              border: Border.all(color: tokens.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s12,
              vertical: AppSpacing.s8,
            ),
            child: TextField(
              controller: _text,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              maxLength: maxNoteTextLength,
              inputFormatters: [
                LengthLimitingTextInputFormatter(maxNoteTextLength),
              ],
              style: AppText.body.copyWith(color: tokens.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: 'What do you want to remember?',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppButton(
            label: 'Add note',
            variant: AppButtonVariant.primary,
            full: true,
            disabled: !_canSubmit,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
