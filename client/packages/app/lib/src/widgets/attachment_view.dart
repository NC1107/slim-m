// SPDX-License-Identifier: Apache-2.0
/// Renders one attachment: an inline image once its bytes arrive, or a
/// filename-and-size chip for anything else. There is no save-to-disk
/// action here; the fetch endpoint is permission-checked and in-memory only
/// (see `providers/attachment_bytes.dart`), and building a per-platform
/// download flow was out of proportion to what this change set out to do.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/attachment_bytes.dart';
import 'message_row_parts.dart' show AttachmentPlaceholder;

/// `1.2 MB`-style formatting; short enough that this app has no existing
/// dependency worth using instead.
String formatByteSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

class AttachmentView extends ConsumerWidget {
  const AttachmentView({super.key, required this.attachment});

  final api.Attachment attachment;

  bool get _isImage => attachment.contentType.startsWith('image/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    if (!_isImage) {
      return Container(
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
            Text(
              attachment.filename,
              style: AppText.ui.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(width: AppSpacing.s8),
            Text(
              formatByteSize(attachment.size),
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      );
    }

    final bytesAsync = ref.watch(attachmentBytesProvider(attachment.id));
    return bytesAsync.when(
      loading: () => const AttachmentPlaceholder(),
      error: (error, _) => Container(
        width: 420,
        height: 168,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.stripe,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Text(
          'Could not load ${attachment.filename}.',
          style: TextStyle(color: tokens.textSecondary),
        ),
      ),
      data: (bytes) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          semanticLabel: attachment.filename,
        ),
      ),
    );
  }
}
