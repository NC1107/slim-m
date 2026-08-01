// SPDX-License-Identifier: Apache-2.0
/// The two native pickers an attachment action can open, and the seam that
/// makes the choice between them testable.
///
/// `file_picker`'s `type:` decides which OS picker a request opens, and the
/// two do not reach the same files. On iOS `FileType.image` opens the
/// Photos-backed `PHPickerViewController`, which cannot see a file that
/// arrived by download, Files, or a messaging app; no filter opens
/// `UIDocumentPickerViewController` instead, which reaches those but not the
/// camera roll. `emoji_upload_card.dart`'s `_pickImageBytes` documented this
/// first; the composer calling `pickFiles()` with no `type:` at all (so it
/// only ever opened the document picker) was the second time it bit, and the
/// reason a phone could never attach a photo straight from the camera roll.
/// Desktop has no such split, one dialog reaches everything, so a desktop
/// caller uses [AttachmentSource.fileBrowser] directly instead of offering a
/// choice with only one real answer.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which native picker a request should open.
enum AttachmentSource {
  /// Photos-backed: `PHPickerViewController` on iOS, the media-only picker
  /// on Android.
  photoLibrary,

  /// The general document browser: `UIDocumentPickerViewController` on iOS,
  /// the SAF browser on Android, the one dialog every desktop platform has.
  fileBrowser,
}

/// Runs one pick and answers what was chosen, or null if nothing was.
typedef AttachmentPicker = Future<FilePickerResult?> Function();

Future<FilePickerResult?> _pickPhotoLibrary() =>
    FilePicker.pickFiles(type: FileType.image);

Future<FilePickerResult?> _pickFileBrowser() => FilePicker.pickFiles();

/// The picker each [AttachmentSource] runs, injectable because `file_picker`
/// has no platform implementation under test: without this seam a widget
/// test can tap a picker action and never get past it, the same gap
/// `emojiImagePickerProvider` closes for the emoji upload card.
final attachmentPickerProvider =
    Provider.family<AttachmentPicker, AttachmentSource>(
      (ref, source) => switch (source) {
        AttachmentSource.photoLibrary => _pickPhotoLibrary,
        AttachmentSource.fileBrowser => _pickFileBrowser,
      },
    );
