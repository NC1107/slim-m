// SPDX-License-Identifier: Apache-2.0
/// Renders one attachment: an inline image once its bytes arrive, or a
/// filename-and-size chip for anything else. There is no save-to-disk
/// action here; the fetch endpoint is permission-checked and in-memory only
/// (see `providers/attachment_bytes.dart`), and building a per-platform
/// download flow was out of proportion to what this change set out to do.
///
/// An inline image opens fullscreen on tap. The chip does not: only the
/// types the server itself renders inline are images this can display, and a
/// pdf has nothing to show in a zoomable viewer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/attachment_bytes.dart';
import 'fullscreen_image_viewer.dart';
import 'message_row_parts.dart' show AttachmentPlaceholder;

/// Mirrors `media::is_inline` in `crates/slimm-server/src/media.rs`: the
/// allowlisted types the server serves inline rather than as a forced
/// download. Spelled out rather than tested with a `image/` prefix, because
/// the server's rule is an allowlist too and an unrecognised type falling
/// back to the filename chip is the safe way to be wrong.
const Set<String> inlineImageTypes = {
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
};

bool isInlineImage(String contentType) =>
    inlineImageTypes.contains(contentType);

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

  bool get _isImage => isInlineImage(attachment.contentType);

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
      error: (error, _) => _tappable(
        label: 'Retry loading ${attachment.filename}',
        onTap: () => ref.invalidate(attachmentBytesProvider(attachment.id)),
        child: Container(
          width: 420,
          height: 168,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tokens.stripe,
            border: Border.all(color: tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Text(
            'Could not load ${attachment.filename}. Tap to retry.',
            style: TextStyle(color: tokens.textSecondary),
          ),
        ),
      ),
      data: (bytes) => _tappable(
        label: 'Open ${attachment.filename} fullscreen',
        onTap: () => showFullscreenImage(
          context,
          filename: attachment.filename,
          bytes: bytes,
        ),
        // Bordered like the chip and error states beside it (border-first
        // elevation), and captioned: a bare rectangle with no name or size
        // read as decoration rather than a file anyone could open.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: tokens.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.control),
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                  semanticLabel: attachment.filename,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              '${attachment.filename} · ${formatByteSize(attachment.size)}',
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tappable({
    required String label,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: onTap, child: child),
      ),
    );
  }
}
