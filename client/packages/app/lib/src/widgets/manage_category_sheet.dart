// SPDX-License-Identifier: Apache-2.0
/// The sheet a category header's context menu opens: rename it, or delete it.
/// `PATCH`/`DELETE /categories/{id}` ([api.SlimmApiChannelAdmin]).
///
/// The counterpart to `manage_channel_sheet.dart` for a category, which has
/// only a name - no topic and no last-channel guard - so this is the same
/// shape with the middle taken out. Deleting a category never deletes its
/// channels; they fall back to uncategorised, which the confirmation says so a
/// manager is not left guessing whether a delete takes the rooms with it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../providers/providers.dart';
import 'confirm_dialog.dart';

/// The server's own ceiling (`CATEGORY_NAME_MAX_CHARS` in
/// `crates/slimm-server/src/http/categories.rs`), so the check here never
/// disagrees with the one the request is judged against.
const int _nameMaxChars = 64;

Future<void> showManageCategorySheet(
  BuildContext context,
  ChannelCategoryRow category,
) {
  return showAppSheet<void>(
    context,
    builder: (context) => _ManageCategorySheet(category: category),
  );
}

class _ManageCategorySheet extends ConsumerStatefulWidget {
  const _ManageCategorySheet({required this.category});

  final ChannelCategoryRow category;

  @override
  ConsumerState<_ManageCategorySheet> createState() =>
      _ManageCategorySheetState();
}

class _ManageCategorySheetState extends ConsumerState<_ManageCategorySheet> {
  late final _name = TextEditingController(text: widget.category.name);
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _dirty => _name.text.trim() != widget.category.name;

  bool get _nameValid =>
      _name.text.trim().isNotEmpty && _name.text.trim().length <= _nameMaxChars;

  bool get _canSave => !_saving && !_deleting && _dirty && _nameValid;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(apiProvider)
          .updateCategory(
            categoryId: widget.category.id,
            name: _name.text.trim(),
          );
      final store = await ref.read(storeProvider.future);
      await store.upsertCategory(updated);
      if (mounted) Navigator.of(context).pop();
    } on api.ApiException catch (e) {
      if (mounted) {
        setState(() => _error = describeApiFailure('rename the category', e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Delete "${widget.category.name}"?',
      message:
          'Its channels are never deleted with it - they fall back to '
          'uncategorised. This cannot be undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep category',
    );
    if (confirmed) await _delete();
  }

  Future<void> _delete() async {
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).deleteCategory(widget.category.id);
      final store = await ref.read(storeProvider.future);
      await store.removeCategory(widget.category.id);
      if (mounted) Navigator.of(context).pop();
    } on api.ApiException catch (e) {
      if (mounted) {
        setState(() => _error = describeApiFailure('delete the category', e));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
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
              'Manage category',
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            AppInput(
              controller: _name,
              placeholder: 'Category name',
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _canSave ? _save() : null,
              semanticLabel: 'Category name',
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.s8),
              AppErrorState(message: _error!),
            ],
            const SizedBox(height: AppSpacing.s12),
            AppButton(
              label: _saving ? 'Saving...' : 'Save changes',
              variant: AppButtonVariant.primary,
              full: true,
              disabled: !_canSave,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.s20),
            Container(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: AppSpacing.s12),
            Text(
              'DANGER ZONE',
              style: AppText.label.copyWith(color: tokens.dangerText),
            ),
            const SizedBox(height: AppSpacing.s8),
            AppButton(
              label: _deleting ? 'Deleting...' : 'Delete category',
              variant: AppButtonVariant.danger,
              full: true,
              disabled: _saving || _deleting,
              onPressed: _confirmDelete,
            ),
          ],
        ),
      ),
    );
  }
}
