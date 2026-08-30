// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The filename-and-size chip for an attachment this app cannot render
/// inline: anything outside `inlineImageTypes` and outside `isVideo`, most
/// commonly a PDF, an archive, or plain text. Split out of
/// `attachment_view.dart` to keep that file within its size budget; see its
/// own doc comment for the full picture of what renders where.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import 'attachment_format.dart';
import 'attachment_save.dart';
import 'run_guarded.dart';

class AttachmentChip extends ConsumerStatefulWidget {
  const AttachmentChip({super.key, required this.attachment});

  final api.Attachment attachment;

  @override
  ConsumerState<AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends ConsumerState<AttachmentChip>
    with GuardedActionState<AttachmentChip> {
  /// Set while the chip's own save action is fetching bytes and handing them
  /// to the platform's save flow; see [_save].
  bool _saving = false;

  api.Attachment get attachment => widget.attachment;

  /// Fetches the attachment through the same cached, authenticated path an
  /// inline image already uses, then hands it to the platform's save flow -
  /// the whole point of this chip existing at all rather than a dead
  /// rectangle. See `attachment_save.dart`.
  Future<void> _save() async {
    setState(() => _saving = true);
    final failure = await saveAttachment(ref, attachment);
    if (!mounted) return;
    setState(() => _saving = false);
    if (failure != null) {
      setActionError(failure);
    } else {
      clearActionError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: 'Save ${attachment.filename}',
          onTap: _save,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.s8,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  border: Border.all(color: tokens.borderSubtle),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flexible, not a bare Text: a long real filename would otherwise overflow the row.
                    Flexible(
                      child: Text(
                        attachment.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.ui.copyWith(color: tokens.textPrimary),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Text(
                      formatByteSize(attachment.size),
                      style: AppText.caption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            AppIcons.download,
                            size: AppSizes.icon16,
                            color: tokens.textSecondary,
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (actionError != null) ...[
          const SizedBox(height: AppSpacing.s4),
          AppErrorState(message: actionError!, onDismiss: clearActionError),
        ],
      ],
    );
  }
}
