// SPDX-License-Identifier: Apache-2.0
/// The strip above the composer while a reply is staged: who it targets, a
/// one-line snippet, and a way to cancel back to an ordinary send.
///
/// Unlike `reply_quote.dart`, this never has a resolution problem to render
/// honestly: the message it names is always one this session just fetched
/// and is looking straight at, since the only way to start a reply is
/// tapping "Reply" on a row already on screen.
///
/// An inset, rounded chip rather than a full-bleed bar: it reads as one
/// recessed quote above the composer, on the design's rounded surfaces,
/// instead of a heavy sharp-cornered strip the width of the pane. A
/// text-less parent with a single image attachment swaps the leading reply
/// arrow for a small decoded thumbnail, so a reply to a photo shows the
/// photo rather than a blank line beside its name.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/attachment_bytes.dart';
import '../providers/media_preferences.dart';
import '../providers/message_extras.dart';
import '../providers/user_profiles.dart';
import 'attachment_view.dart' show isInlineImage;
import 'author_label.dart';
import 'image_decode.dart';

/// The square a reply's own attachment thumbnail draws into - small enough
/// that the banner stays one compact row rather than growing to fit a
/// preview-sized image.
const double _thumbnailEdge = AppSpacing.s24;

class ReplyBanner extends ConsumerWidget {
  const ReplyBanner({super.key, required this.message, required this.onCancel});

  final Message message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final label = authorLabel(
      authorId: message.authorId,
      cachedDisplayName: message.authorDisplayName,
      profiles: ref.watch(batchProfilesControllerProvider),
    );
    final attachments = ref.watch(
      messageExtrasProvider.select(
        (extras) => extras[message.id]?.attachments ?? const [],
      ),
    );
    // A text-less parent is named by what it carried, not left blank.
    final text = message.content.replaceAll('\n', ' ').trim();
    final snippet = text.isNotEmpty ? text : _attachmentSummary(attachments);
    // Only a single-attachment, text-less parent gets a thumbnail: several attachments already read as a count.
    final soleAttachment = text.isEmpty && attachments.length == 1
        ? attachments.single
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s8,
        AppSpacing.s8,
        AppSpacing.s8,
        AppSpacing.s4,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceSunken,
          borderRadius: BorderRadius.circular(AppRadii.control),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s12,
            vertical: AppSpacing.s8,
          ),
          child: Row(
            children: [
              soleAttachment == null
                  ? Icon(AppIcons.reply, size: 14, color: tokens.textSecondary)
                  : _ReplyAttachmentThumbnail(attachment: soleAttachment),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Replying to $label',
                        style: AppText.caption.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: AppWeights.semi,
                        ),
                      ),
                      if (snippet.isNotEmpty)
                        TextSpan(
                          text: '  $snippet',
                          style: AppText.caption.copyWith(
                            color: tokens.textSecondary,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppIconButton(
                icon: AppIcons.dismiss,
                semanticLabel: 'Cancel reply',
                tooltip: 'Cancel reply',
                size: AppIconButtonSize.sm,
                onPressed: onCancel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a text-less parent carried, so its reply chip names something rather
/// than trailing off after the author: one image reads as "Photo", one file as
/// its own name, several as a plain count.
String _attachmentSummary(List<api.Attachment> attachments) {
  if (attachments.isEmpty) return '';
  if (attachments.length > 1) return '${attachments.length} attachments';
  final only = attachments.first;
  return only.contentType.startsWith('image/') ? 'Photo' : only.filename;
}

/// The reply banner's leading glyph when its sole parent attachment is an
/// image: a real decoded thumbnail rather than the generic reply arrow, so a
/// reply to a photo reads as a photo at a glance instead of a blank line
/// beside its filename.
///
/// Stays a file glyph, never a fetch, for anything the transcript itself
/// would not decode inline (see [isInlineImage]) and for a reader who has
/// turned off auto-download - a staged reply is not the place to spend their
/// data budget on an image they have not asked to open.
class _ReplyAttachmentThumbnail extends ConsumerWidget {
  const _ReplyAttachmentThumbnail({required this.attachment});

  final api.Attachment attachment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    Widget frame(Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: SizedBox(
        width: _thumbnailEdge,
        height: _thumbnailEdge,
        child: ColoredBox(color: tokens.surfaceRaised, child: child),
      ),
    );
    Widget glyph(IconData icon) =>
        Center(child: Icon(icon, size: 12, color: tokens.textSecondary));

    if (!isInlineImage(attachment.contentType)) {
      return frame(glyph(AppIcons.attachFile));
    }
    final autoDownload = ref.watch(mediaAutoDownloadControllerProvider);
    if (autoDownload == MediaAutoDownload.manual) {
      return frame(glyph(AppIcons.image));
    }
    final bytesAsync = ref.watch(attachmentBytesProvider(attachment.id));
    return frame(
      bytesAsync.when(
        data: (bytes) => Image.memory(
          bytes,
          fit: BoxFit.cover,
          cacheWidth: decodeEdge(context, _thumbnailEdge),
          cacheHeight: decodeEdge(context, _thumbnailEdge),
          errorBuilder: (_, _, _) => glyph(AppIcons.image),
        ),
        loading: () => const SizedBox.shrink(),
        error: (_, _) => glyph(AppIcons.image),
      ),
    );
  }
}
