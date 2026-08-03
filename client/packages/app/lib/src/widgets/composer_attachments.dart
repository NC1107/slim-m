// SPDX-License-Identifier: Apache-2.0
/// A composer's staged attachments: files already uploaded, awaiting only
/// the send that will point them at a channel.
///
/// Split out of `composer.dart`, which had no line budget left for it once
/// it also had to stop a stale attachment carrying across a channel switch
/// (see [ComposerAttachments.resetForChannelSwitch]). A mixin rather than a
/// plain helper object: the picking and upload paths already needed
/// `_ComposerState`'s own `ref`, `context` and `setState` at every step, and
/// a helper object would only have re-invented them behind a bag of
/// callbacks.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import '../api_failure.dart';
import '../providers/providers.dart';
import 'attachment_picker.dart';

/// Mixed into a composer's own `State` to hold and stage attachments.
///
/// `on ConsumerState<T>` rather than a narrower bound: it needs `ref` for the
/// upload, `context` for the failure `SnackBar`s, and `setState`, all of
/// which `ConsumerState` already supplies to whatever widget mixes this in.
mixin ComposerAttachments<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  bool uploading = false;
  final List<api.Attachment> pendingAttachments = [];
  String? clipboardPasteError;

  /// A staged attachment is already uploaded, server-side, real cost, and
  /// unlike a composer's text (see `channel_drafts.dart`) nothing here
  /// restores it for a later return to this channel. Carrying it silently
  /// into whatever channel comes up next would risk sending it there by
  /// mistake instead - the exact "stale target" shape a draft must not
  /// reintroduce.
  void resetForChannelSwitch() {
    setState(() {
      pendingAttachments.clear();
      clipboardPasteError = null;
    });
  }

  void removeAttachment(api.Attachment attachment) {
    setState(() => pendingAttachments.remove(attachment));
  }

  void setClipboardPasteError(String? message) {
    if (mounted) setState(() => clipboardPasteError = message);
  }

  /// Called once a send has actually gone out with these ids.
  void clearSentAttachments() {
    if (mounted) setState(() => pendingAttachments.clear());
  }

  /// Re-focuses [focus] on every exit, including a cancelled pick: the
  /// native picker takes focus with it, and without this the caret never
  /// comes back and typing goes nowhere.
  Future<void> pickAttachment(
    AttachmentSource source, {
    required FocusNode focus,
  }) async {
    final FilePickerResult? result;
    try {
      result = await ref.read(attachmentPickerProvider(source))();
    } catch (e) {
      if (!mounted) return;
      focus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file picker.')),
      );
      return;
    }
    if (!mounted) return;
    focus.requestFocus();
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final file = files.first;
    // readAsBytes streams from disk; eager PlatformFile.bytes OOMs on a large pick.
    await stageAttachment(await file.readAsBytes(), file.name);
  }

  /// Uploads bytes from wherever they came from and, on success, stages the
  /// resulting attachment. Shared by the file picker and a pasted image so
  /// neither invents its own way onto the send path.
  Future<void> stageAttachment(Uint8List bytes, String filename) async {
    if (!mounted) return;
    setState(() => uploading = true);
    try {
      final attachment = await ref
          .read(apiProvider)
          .uploadAttachment(bytes, filename: filename);
      if (!mounted) return;
      setState(() {
        pendingAttachments.add(attachment);
        uploading = false;
      });
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() => uploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeApiFailure('attach the file', e))),
      );
    }
  }
}
