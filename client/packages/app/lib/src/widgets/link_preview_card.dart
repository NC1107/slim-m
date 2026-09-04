// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The card a pasted URL unfurls into below a message: the linked page's
/// site name, title, description and proxied image, one card per link.
///
/// A missing or failed preview renders nothing - never an error surface -
/// since a link that fails to unfurl is not something the reader did wrong,
/// and the link itself already rendered as a tappable [InlineLink] in the
/// body above this.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/attachment_preview_quality.dart';
import '../providers/link_preview.dart';
import '../providers/media_preferences.dart';
import 'attachment_reveal.dart';
import 'attachment_view.dart' show kInlineImageMax;
import 'image_decode.dart';

/// One card per URL, below a message's own text. Callers cap [urls] before
/// handing them here; this renders exactly what it is given.
class LinkPreviewList extends StatelessWidget {
  const LinkPreviewList({super.key, required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final url in urls)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s4),
            child: LinkPreviewCard(url: url),
          ),
      ],
    );
  }
}

class LinkPreviewCard extends ConsumerStatefulWidget {
  const LinkPreviewCard({super.key, required this.url});

  final String url;

  @override
  ConsumerState<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends ConsumerState<LinkPreviewCard> {
  /// Set once the reader taps a held image; see [AttachmentView]'s own
  /// field of the same name and reason.
  bool _revealed = false;

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final preview = ref.watch(linkPreviewProvider(widget.url)).valueOrNull;
    if (preview == null) return const SizedBox.shrink();
    final hasText =
        preview.siteName != null ||
        preview.title != null ||
        preview.description != null;
    if (!hasText && preview.imageToken == null) {
      return const SizedBox.shrink();
    }

    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Semantics(
      button: true,
      label: 'Open link preview for ${preview.title ?? widget.url}',
      onTap: _open,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMessageColumnMax),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: tokens.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadii.control),
              ),
              padding: const EdgeInsets.all(AppSpacing.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (preview.siteName case final siteName?)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          AppIcons.link,
                          size: 12,
                          color: tokens.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.s4),
                        Flexible(
                          child: Text(
                            siteName,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.caption.copyWith(
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (preview.title case final title?)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s4),
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.body.copyWith(
                          fontWeight: AppWeights.semi,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  if (preview.description case final description?)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s4),
                      child: Text(
                        description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.caption.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  if (preview.imageToken case final token?)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s8),
                      child: _LinkPreviewImage(
                        token: token,
                        revealed: _revealed,
                        onReveal: () => setState(() => _revealed = true),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The preview image, honoring the same media auto-download and preview
/// quality settings [AttachmentView] applies to an inline attachment image -
/// text above this always shows, but a fetch this large only happens when
/// the reader's own settings allow it.
class _LinkPreviewImage extends ConsumerWidget {
  const _LinkPreviewImage({
    required this.token,
    required this.revealed,
    required this.onReveal,
  });

  final String token;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoDownload = ref.watch(mediaAutoDownloadControllerProvider);
    if (autoDownload == MediaAutoDownload.manual && !revealed) {
      return AttachmentRevealTile(
        icon: AppIcons.image,
        line: 'Tap to load preview',
        caption: 'Link preview image',
        maxEdge: kInlineImageMax,
        onReveal: onReveal,
      );
    }

    final previewScale = ref
        .watch(attachmentPreviewQualityControllerProvider)
        .decodeScale;
    final decodeWidth = decodeEdge(
      context,
      kInlineImageMax,
      scale: previewScale,
    );
    final bytesAsync = ref.watch(linkPreviewImageBytesProvider(token));
    final bytes = bytesAsync.valueOrNull;
    if (bytes == null) return const SizedBox.shrink();

    final tokens = Theme.of(context).extension<AppTokens>()!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.control),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: kInlineImageMax,
          maxHeight: kInlineImageMax,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            cacheWidth: decodeWidth,
            errorBuilder: (context, error, stackTrace) =>
                const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
