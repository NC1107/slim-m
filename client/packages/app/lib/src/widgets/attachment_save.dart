// SPDX-License-Identifier: Apache-2.0
/// Saving any attachment to wherever the platform's own picker offers.
///
/// `file_picker`'s `saveFile` already differs correctly per platform under
/// one call: a native Save dialog on Windows/macOS/Linux, the Storage Access
/// Framework's create-document flow on Android, a document-picker export on
/// iOS, and a plain anchor-with-`download` click on web (verified by reading
/// each platform implementation in the `file_picker` source rather than
/// assuming). It is already a dependency of this app (attachment upload uses
/// it to pick files), so this adds no new one and no conditional import: the
/// per-platform difference belongs entirely to a library this app already
/// trusts.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import '../api_failure.dart';
import '../providers/attachment_bytes.dart';

/// Fetches [attachment]'s bytes through the same cached, authenticated path
/// inline images already use, then hands them to the platform's save flow.
///
/// Returns null on success, or a sentence for [AppErrorState] on failure -
/// the same contract `runGuarded` returns, so a caller with its own
/// `GuardedActionState` renders it the same way. A user cancelling the save
/// dialog is not a failure: `saveFile` returns null for that and this
/// returns null too.
Future<String?> saveAttachment(WidgetRef ref, api.Attachment attachment) async {
  try {
    final bytes = await ref.read(attachmentBytesProvider(attachment.id).future);
    await FilePicker.saveFile(fileName: attachment.filename, bytes: bytes);
    return null;
  } on api.ApiException catch (e) {
    return describeApiFailure('save ${attachment.filename}', e);
  } catch (e) {
    return 'Could not save ${attachment.filename}.';
  }
}
