// SPDX-License-Identifier: Apache-2.0
/// The member popover's "Private note" row: `GET`/`PUT
/// /users/{userId}/note` (`SlimmApi.getUserNote`/`setUserNote`), the note
/// itself held in [userNoteProvider].
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

import '../api_failure.dart';
import '../providers/providers.dart';
import '../providers/user_notes.dart';
import 'run_guarded.dart';

/// Opens the sheet for the caller's own note about [subjectId], named
/// [subjectName] in its title.
Future<void> showMemberNoteSheet(
  BuildContext context, {
  required String subjectId,
  required String subjectName,
}) {
  return showAppSheet<void>(
    context,
    builder: (context) =>
        _MemberNoteSheet(subjectId: subjectId, subjectName: subjectName),
  );
}

/// The member popover's own row for [showMemberNoteSheet], split out of
/// `member_profile.dart` so that file's `rows` list stays one line per menu
/// entry rather than carrying this row's `onTap` closure inline.
class MemberNoteMenuItem extends StatelessWidget {
  const MemberNoteMenuItem({
    super.key,
    required this.host,
    required this.subjectId,
    required this.subjectName,
    required this.onDone,
  });

  /// A context that outlives the popover, passed straight to
  /// [showMemberNoteSheet] - see `member_profile.dart`'s own `host` doc.
  final BuildContext host;
  final String subjectId;
  final String subjectName;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => AppMenuItem(
    label: 'Private note...',
    leading: AppIcons.note,
    submenu: true,
    onTap: () {
      onDone();
      unawaited(
        showMemberNoteSheet(
          host,
          subjectId: subjectId,
          subjectName: subjectName,
        ),
      );
    },
  );
}

class _MemberNoteSheet extends ConsumerStatefulWidget {
  const _MemberNoteSheet({required this.subjectId, required this.subjectName});

  final String subjectId;
  final String subjectName;

  @override
  ConsumerState<_MemberNoteSheet> createState() => _MemberNoteSheetState();
}

class _MemberNoteSheetState extends ConsumerState<_MemberNoteSheet>
    with GuardedActionState<_MemberNoteSheet> {
  final _controller = TextEditingController();
  bool _saving = false;

  /// The fetched note is seeded into [_controller] once: after that, this
  /// sheet owns the field and must not overwrite what is being typed if the
  /// underlying provider happens to rebuild.
  bool _seeded = false;
  String _original = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _seed(api.UserNote note) {
    if (_seeded) return;
    _seeded = true;
    _original = note.body ?? '';
    _controller.text = _original;
  }

  bool get _dirty => _controller.text.trim() != _original;
  bool get _valid => _controller.text.trim().length <= api.kUserNoteMaxChars;
  bool get _canSave => _seeded && !_saving && _dirty && _valid;
  bool get _canClear =>
      _seeded &&
      !_saving &&
      (_controller.text.trim().isNotEmpty || _original.isNotEmpty);

  Future<void> _apply(String text) async {
    setState(() => _saving = true);
    final ok = await guard(
      whatFailed: 'save this note',
      action: () async {
        await ref.read(apiProvider).setUserNote(widget.subjectId, text);
        ref.invalidate(userNoteProvider(widget.subjectId));
      },
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _save() => _apply(_controller.text.trim());

  Future<void> _clear() {
    _controller.clear();
    return _apply('');
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final noteAsync = ref.watch(userNoteProvider(widget.subjectId));
    // Seeds the field the moment the fetch resolves, on whichever build that happens to land on - already-cached data included.
    noteAsync.whenData(_seed);
    final length = _controller.text.trim().length;

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
              'Private note about ${widget.subjectName}',
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              'Only you can see this.',
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
            const SizedBox(height: AppSpacing.s12),
            switch (noteAsync) {
              AsyncError(:final error) => AppErrorState(
                message: error is api.ApiException
                    ? describeApiFailure('load this note', error)
                    : 'Could not load this note.',
              ),
              _ => _NoteField(
                controller: _controller,
                enabled: _seeded && !_saving,
                onChanged: (_) => setState(() {}),
              ),
            },
            const SizedBox(height: AppSpacing.s4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$length/${api.kUserNoteMaxChars}',
                style: AppText.micro.copyWith(
                  color: length > api.kUserNoteMaxChars
                      ? tokens.dangerText
                      : tokens.textSecondary,
                ),
              ),
            ),
            if (actionError != null) ...[
              const SizedBox(height: AppSpacing.s8),
              AppErrorState(message: actionError!, onDismiss: clearActionError),
            ],
            const SizedBox(height: AppSpacing.s12),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Clear',
                    variant: AppButtonVariant.ghost,
                    disabled: !_canClear,
                    onPressed: _clear,
                  ),
                ),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: AppButton(
                    label: _saving ? 'Saving...' : 'Save',
                    variant: AppButtonVariant.primary,
                    disabled: !_canSave,
                    onPressed: _save,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The multi-line field itself, split out only so [_MemberNoteSheetState]'s
/// build method reads as one switch over the fetch rather than a nested
/// ternary tree.
class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
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
        controller: controller,
        enabled: enabled,
        minLines: 3,
        maxLines: 6,
        style: AppText.body.copyWith(color: tokens.textPrimary),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          hintText: 'Only you can see this note',
        ),
        onChanged: onChanged,
      ),
    );
  }
}
