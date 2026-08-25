// SPDX-License-Identifier: Apache-2.0
/// The performance pane: the two dials that trade image memory for sharpness,
/// or the reverse.
///
/// Preview quality decodes each inline attachment smaller; the image-cache cap
/// bounds how much decoded-image memory is kept for reuse. They are paired here
/// on purpose - a data-saver preview and a large cache together hold far more
/// attachments ready to scroll back to than either does alone, since each one
/// resident costs a fraction as much.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/attachment_preview_quality.dart';
import '../providers/image_cache_preference.dart';
import 'settings_section_header.dart';
import 'settings_select_row.dart';

class PerformanceSettingsSection extends ConsumerWidget {
  const PerformanceSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsSectionCard(
      children: [
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
      ],
    );
  }
}
