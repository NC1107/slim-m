// SPDX-License-Identifier: Apache-2.0
/// The performance pane: the local dials for what media does on its own, plus
/// how much history a scroll-back fetches.
///
/// Auto-download decides whether images fetch on sight (data); autoplay decides
/// whether gifs animate on sight (battery/CPU); preview quality decides how
/// sharply each inline preview decodes (memory); and the image-cache cap bounds
/// how much decoded-image memory is kept for reuse (memory). The media four are
/// paired on purpose - a data-saver preview and a large cache together hold far
/// more attachments ready to scroll back to than either does alone, since each
/// one resident costs a fraction as much. Message page size is the odd one out:
/// a network lever, how many older messages one backwards page asks for.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/attachment_preview_quality.dart';
import '../providers/image_cache_preference.dart';
import '../providers/media_preferences.dart';
import '../providers/message_page_size.dart';
import 'settings_section_header.dart';
import 'settings_select_row.dart';

class PerformanceSettingsSection extends ConsumerWidget {
  const PerformanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSectionCard(
      children: [
        SettingsSelectRow<MediaAutoDownload>(
          label: 'Auto-download media',
          sheetTitle: 'Auto-download media',
          value: ref.watch(mediaAutoDownloadControllerProvider),
          choices: [
            for (final value in MediaAutoDownload.values)
              SettingsChoice(value: value, label: value.label),
          ],
          sheetFootnote:
              'Whether images fetch as they scroll into view or wait for a '
              'tap. Only when tapped saves data on a metered connection; '
              'nothing downloads until you ask.',
          onChanged: (next) => ref
              .read(mediaAutoDownloadControllerProvider.notifier)
              .select(next),
        ),
        SettingsSelectRow<GifAutoplay>(
          label: 'Autoplay GIFs',
          sheetTitle: 'Autoplay GIFs',
          value: ref.watch(gifAutoplayControllerProvider),
          choices: [
            for (final value in GifAutoplay.values)
              SettingsChoice(value: value, label: value.label),
          ],
          sheetFootnote:
              'Whether gifs animate on their own. Tap to play holds each on '
              'its first frame until tapped, which saves battery and CPU since '
              'an animating gif re-decodes every frame the whole time.',
          onChanged: (next) =>
              ref.read(gifAutoplayControllerProvider.notifier).select(next),
        ),
        SettingsSelectRow<AttachmentPreviewQuality>(
          label: 'Attachment preview quality',
          sheetTitle: 'Attachment preview quality',
          value: ref.watch(attachmentPreviewQualityControllerProvider),
          choices: [
            for (final quality in AttachmentPreviewQuality.values)
              SettingsChoice(value: quality, label: quality.label),
          ],
          sheetFootnote:
              'How sharply images and gifs are drawn inline. A lower setting '
              'decodes each preview smaller, so far more of them fit in the '
              'image cache at once; opening one always shows it full resolution.',
          onChanged: (next) => ref
              .read(attachmentPreviewQualityControllerProvider.notifier)
              .select(next),
        ),
        SettingsSelectRow<int>(
          label: 'Image cache',
          sheetTitle: 'Image cache limit',
          value: ref.watch(imageCacheLimitControllerProvider),
          choices: [
            for (final mb in imageCacheLimitChoicesMb)
              SettingsChoice(
                value: mb,
                label: mb == defaultImageCacheLimitMb
                    ? '$mb MB (default)'
                    : '$mb MB',
              ),
          ],
          sheetFootnote:
              'How much memory to spend keeping recently-seen images ready to '
              'show instantly. A lower limit saves memory; images you scroll '
              'back to redraw a moment slower, and are never re-downloaded.',
          onChanged: (next) =>
              ref.read(imageCacheLimitControllerProvider.notifier).select(next),
        ),
        SettingsSelectRow<MessagePageSize>(
          label: 'Message page size',
          sheetTitle: 'Message page size',
          value: ref.watch(messagePageSizeControllerProvider),
          choices: [
            for (final value in MessagePageSize.values)
              SettingsChoice(value: value, label: value.label),
          ],
          sheetFootnote:
              'How many older messages to load each time you scroll back. A '
              'smaller page is a lighter, snappier request; a larger one reads '
              'a long history in fewer steps.',
          onChanged: (next) =>
              ref.read(messagePageSizeControllerProvider.notifier).select(next),
        ),
      ],
    );
  }
}
