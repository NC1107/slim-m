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
import '../providers/attachment_preview_quality.dart';
import 'fullscreen_image_viewer.dart';
import 'image_decode.dart';
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

/// The largest an image is drawn inline, in logical pixels, on both axes.
///
/// Half [kMessageColumnMax]. An uncapped preview let one image fill a desktop
/// screen and push the rest of the conversation off it, and the height was
/// unbounded entirely, so a tall narrow image was worse than a wide one.
///
/// Capping both axes rather than the width alone is the point: the transcript
/// is the conversation, and an attachment is a thing in it. Full size is one
/// tap away and already built.
const double kInlineImageMax = kMessageColumnMax / 2;

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

class AttachmentView extends ConsumerStatefulWidget {
  const AttachmentView({super.key, required this.attachment});

  final api.Attachment attachment;

  @override
  ConsumerState<AttachmentView> createState() => _AttachmentViewState();
}

/// Stateful only for [_heroTag]: an attachment is content-addressed, so one
/// id legitimately rides on more than one message, and two rows showing the
/// same image with one shared tag would throw the moment a flight starts.
/// An identity object held by this element is unique per mounted view and
/// stable across rebuilds, which is exactly what a hero tag needs.
class _AttachmentViewState extends ConsumerState<AttachmentView> {
  final Object _heroTag = Object();

  api.Attachment get attachment => widget.attachment;

  bool get _isImage => isInlineImage(attachment.contentType);

  @override
  Widget build(BuildContext context) {
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
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
        ),
      );
    }

    final bytesAsync = ref.watch(attachmentBytesProvider(attachment.id));
    final previewScale = ref
        .watch(attachmentPreviewQualityControllerProvider)
        .decodeScale;
    return bytesAsync.when(
      loading: () => const AttachmentPlaceholder(),
      error: (error, _) => _tappable(
        label: 'Retry loading ${attachment.filename}',
        onTap: () => ref.invalidate(attachmentBytesProvider(attachment.id)),
        child: _FailureBox(
          tokens: tokens,
          message: 'Could not load ${attachment.filename}. Tap to retry.',
          width: 420,
          height: 168,
        ),
      ),
      data: (bytes) => _tappable(
        label: 'Open ${attachment.filename} fullscreen',
        onTap: () => showFullscreenImage(
          context,
          filename: attachment.filename,
          bytes: bytes,
          heroTag: _heroTag,
        ),
        // Bordered like the chip and error states beside it (border-first
        // elevation), and captioned: a bare rectangle with no name or size
        // read as decoration rather than a file anyone could open.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Hero(
              tag: _heroTag,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.borderSubtle),
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.control),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kInlineImageMax,
                      maxHeight: kInlineImageMax,
                    ),
                    // Never decodes wider than the transcript can draw it.
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      semanticLabel: attachment.filename,
                      cacheWidth: decodeEdge(
                        context,
                        kInlineImageMax,
                        scale: previewScale,
                      ),
                      // Bytes can decode-fail after a successful fetch; without this it paints as Flutter's raw error box.
                      errorBuilder: (context, error, stackTrace) => _FailureBox(
                        tokens: tokens,
                        message: 'Could not open ${attachment.filename}.',
                        width: kInlineImageMax,
                        height: 168,
                      ),
                    ),
                  ),
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

/// The bordered "something went wrong" placeholder shared by a failed fetch
/// and a fetch that succeeded but handed back bytes the codec refuses to
/// decode - the same box, the same stripe token, so both read as one visual
/// language rather than two.
class _FailureBox extends StatelessWidget {
  const _FailureBox({
    required this.tokens,
    required this.message,
    required this.width,
    required this.height,
  });

  final AppTokens tokens;
  final String message;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.stripe,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Text(message, style: TextStyle(color: tokens.textSecondary)),
    );
  }
}
