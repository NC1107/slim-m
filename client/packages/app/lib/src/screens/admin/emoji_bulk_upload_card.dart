// SPDX-License-Identifier: Apache-2.0
/// Bulk emoji upload from a `.zip` - backlog #137.
///
/// One custom emoji per image inside the zip, named after its file stem
/// Discord-style (`party_blob.gif` becomes `:party_blob:`), through the same
/// name rules `EmojiUploadCard` applies one at a time; see
/// `emoji_bulk_plan.dart` for the pure derivation this widget only drives.
///
/// Uploads run one at a time rather than concurrently: `POST /emoji` is rate
/// limited per caller (`Class::Upload` on the server), and a burst of
/// parallel requests would just turn into a burst of 429s the sequential
/// order avoids for free. Each result is kept and shown in a final summary
/// rather than stopping at the first failure, since one bad file in a
/// hundred should not cost the other ninety-nine.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../api_failure.dart';
import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../widgets/settings_section_header.dart';
import 'emoji_bulk_plan.dart';
import 'emoji_name.dart';

/// Picks a zip file and returns its bytes, or null if nothing was chosen.
typedef EmojiZipPicker = Future<List<int>?> Function();

/// Injectable for the same reason `emojiImagePickerProvider` is:
/// `file_picker` has no platform implementation under test.
final emojiZipPickerProvider = Provider<EmojiZipPicker>((ref) => _pickZipBytes);

Future<List<int>?> _pickZipBytes() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['zip'],
  );
  final files = result?.files ?? const <PlatformFile>[];
  if (files.isEmpty) return null;
  // readAsBytes streams from disk since eager loading OOMs on a large pick.
  return files.first.readAsBytes();
}

enum _Outcome { uploaded, failed }

class _Result {
  const _Result({required this.fileName, required this.outcome, this.reason});

  final String fileName;
  final _Outcome outcome;
  final String? reason;
}

class EmojiBulkUploadCard extends ConsumerStatefulWidget {
  const EmojiBulkUploadCard({super.key});

  @override
  ConsumerState<EmojiBulkUploadCard> createState() =>
      _EmojiBulkUploadCardState();
}

/// Watches `customEmojiProvider` in [build], not only reads it from
/// `_pickAndRun`: that way the deployment's current emoji names are already
/// resolved by the time a tap can reach the collision check, rather than
/// depending on whichever sibling widget happens to watch the provider first.
class _EmojiBulkUploadCardState extends ConsumerState<EmojiBulkUploadCard> {
  bool _running = false;
  int _current = 0;
  int _total = 0;
  String? _refusal;
  List<SkippedZipEntry> _skipped = const [];
  List<_Result> _results = const [];

  Future<void> _pickAndRun() async {
    final List<int>? bytes;
    try {
      bytes = await ref.read(emojiZipPickerProvider)();
    } catch (e) {
      _refuse('Could not open the file picker.');
      return;
    }
    if (bytes == null || !mounted) return;

    final List<ZipEntryData> entries;
    try {
      entries = decodeEmojiZipEntries(bytes);
    } catch (e) {
      _refuse('That file could not be read as a zip.');
      return;
    }

    final existing = ref.read(customEmojiProvider).valueOrNull ?? const [];
    final plan = planEmojiZip(
      entries,
      existingNames: {for (final e in existing) e.name},
    );
    if (plan.uploads.isEmpty && plan.skipped.isEmpty) {
      _refuse('That zip has no images in it.');
      return;
    }

    setState(() {
      _running = true;
      _refusal = null;
      _skipped = plan.skipped;
      _results = const [];
      _current = 0;
      _total = plan.uploads.length;
    });

    final results = <_Result>[];
    for (final upload in plan.uploads) {
      if (!mounted) return;
      setState(() => _current++);
      try {
        await ref
            .read(apiProvider)
            .uploadCustomEmoji(upload.bytes, name: upload.name);
        results.add(
          _Result(fileName: upload.fileName, outcome: _Outcome.uploaded),
        );
      } on api.ApiException catch (e) {
        results.add(
          _Result(
            fileName: upload.fileName,
            outcome: _Outcome.failed,
            reason: describeApiFailure('add ${emojiShortcode(upload.name)}', e),
          ),
        );
      }
      if (!mounted) return;
      setState(() => _results = List.of(results));
    }

    if (results.any((r) => r.outcome == _Outcome.uploaded)) {
      ref.invalidate(customEmojiProvider);
    }
    if (!mounted) return;
    setState(() => _running = false);
  }

  void _refuse(String message) {
    if (!mounted) return;
    setState(() {
      _running = false;
      _refusal = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final finished = !_running && (_results.isNotEmpty || _skipped.isNotEmpty);
    ref.watch(customEmojiProvider); // see the class doc comment for why

    return SettingsSectionCard(
      title: 'Bulk import from a zip',
      children: [
        Text(
          'Each image inside becomes an emoji named after its file, '
          'Discord-style: party_blob.gif becomes :party_blob:.',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        const SizedBox(height: AppSpacing.s12),
        if (_refusal case final refusal?) ...[
          AppCallout(tone: AppCalloutTone.warn, child: Text(refusal)),
          const SizedBox(height: AppSpacing.s12),
        ],
        if (_running) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              'Uploading $_current of $_total...',
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          LinearProgressIndicator(
            value: _total == 0 ? null : (_current - 1) / _total,
          ),
          const SizedBox(height: AppSpacing.s12),
        ],
        if (finished) ...[
          _BulkSummary(results: _results, skipped: _skipped),
          const SizedBox(height: AppSpacing.s12),
        ],
        AppButton(
          label: finished ? 'Import another zip' : 'Choose a zip file',
          icon: AppIcons.fileArchive,
          full: true,
          disabled: _running,
          onPressed: _pickAndRun,
        ),
      ],
    );
  }
}

/// The finished (or partly finished) run's own report: how many of the
/// planned uploads succeeded, and every failure or pre-upload skip with its
/// reason, so a shorter list than the zip held is explained rather than
/// silently swallowed.
class _BulkSummary extends StatelessWidget {
  const _BulkSummary({required this.results, required this.skipped});

  final List<_Result> results;
  final List<SkippedZipEntry> skipped;

  @override
  Widget build(BuildContext context) {
    final succeeded = results
        .where((r) => r.outcome == _Outcome.uploaded)
        .length;
    final failed = results.where((r) => r.outcome == _Outcome.failed);
    final total = results.length + skipped.length;
    final allGood = succeeded == total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCallout(
          tone: allGood ? AppCalloutTone.accent : AppCalloutTone.warn,
          child: Text(
            'Added $succeeded of $total image${total == 1 ? '' : 's'}.',
          ),
        ),
        for (final r in failed)
          _FailureLine(fileName: r.fileName, reason: r.reason ?? 'failed'),
        for (final s in skipped)
          _FailureLine(fileName: s.fileName, reason: s.reason),
      ],
    );
  }
}

class _FailureLine extends StatelessWidget {
  const _FailureLine({required this.fileName, required this.reason});

  final String fileName;
  final String reason;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8),
      child: Text(
        '$fileName: $reason',
        style: AppText.caption.copyWith(color: tokens.dangerText),
      ),
    );
  }
}
