// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The card's own private-note field: `GET`/`PUT /users/{userId}/note`
/// (`SlimmApi.getUserNote`/`setUserNote`), the note itself held in
/// [userNoteProvider].
///
/// Replaces `member_note_sheet.dart`'s "Private note..." row and its own
/// sheet: the design puts the field inline on the card, labelled only-you,
/// saved on blur rather than behind a second surface for one line of text.
///
/// Caller-private, always - this is never a note the subject or anyone else
/// wrote, only what the caller themselves keeps about them, and it is never
/// shown to the subject. An empty or whitespace-only body clears it rather
/// than storing a blank one, the same convention `status_editor_sheet.dart`
/// follows for the caller's own status text.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../providers/user_notes.dart';

/// An inline field on the card for the caller's own note about [subjectId].
/// Dashed border until a note has been written; saved when the field loses
/// focus, not on every keystroke.
class MemberProfileNoteField extends ConsumerStatefulWidget {
  const MemberProfileNoteField({super.key, required this.subjectId});

  final String subjectId;

  @override
  ConsumerState<MemberProfileNoteField> createState() =>
      _MemberProfileNoteFieldState();
}

class _MemberProfileNoteFieldState
    extends ConsumerState<MemberProfileNoteField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _seeded = false;
  String _original = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _seed(api.UserNote note) {
    if (_seeded) return;
    _seeded = true;
    _original = note.body ?? '';
    _controller.text = _original;
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) return;
    final trimmed = _controller.text.trim();
    if (trimmed == _original) return;
    unawaited(_save(trimmed));
  }

  Future<void> _save(String trimmed) async {
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).setUserNote(widget.subjectId, trimmed);
      _original = trimmed;
      ref.invalidate(userNoteProvider(widget.subjectId));
    } on api.ApiException {
      // Low-stakes: the field just keeps the unsaved text, no error banner.
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final noteAsync = ref.watch(userNoteProvider(widget.subjectId));
    noteAsync.whenData(_seed);
    final filled = _controller.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        0,
        AppSpacing.s12,
        AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomPaint(
            foregroundPainter: filled
                ? null
                : _DashedRectPainter(color: tokens.borderSubtle),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.control),
                border: filled ? Border.all(color: tokens.borderSubtle) : null,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s8,
                vertical: 6,
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: _seeded && !_saving,
                maxLength: api.kUserNoteMaxChars,
                maxLines: null,
                style: AppText.caption.copyWith(color: tokens.textPrimary),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  counterText: '',
                  hintText: 'Add a private note',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'only you',
            style: AppText.micro.copyWith(color: tokens.textDisabled),
          ),
        ],
      ),
    );
  }
}

/// A hairline dashed rectangle, drawn with [CustomPainter] since Flutter has
/// no built-in dashed [Border]. Only the placeholder state uses this; a
/// written note gets the plain solid border every other field in this system
/// has, so the dash reads as "empty", not as this field's permanent style.
class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter({required this.color});

  final Color color;

  static const _dashWidth = 3.0;
  static const _dashGap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(AppRadii.control),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) =>
      oldDelegate.color != color;
}
