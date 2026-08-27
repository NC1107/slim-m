// SPDX-License-Identifier: Apache-2.0
/// The composer's GIF picker: a search field, a debounced request, and a
/// grid of results streamed through this deployment's own server. Nothing
/// here ever reaches the configured provider directly - `searchGifs`,
/// `fetchGifPreview` and `selectGif` all proxy through
/// [SlimmApiGifs] - and the whole surface is only ever shown when
/// `Version.gifSearchEnabled` is true; see `composer.dart` for that check.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../providers/gif_preview_bytes.dart';
import '../providers/providers.dart';
import 'composer_attachments.dart';
import 'image_decode.dart';

/// How long a pause in typing must last before a search actually fires, so a
/// fast typist does not spend a request per keystroke.
const _searchDebounce = Duration(milliseconds: 400);

/// A ceiling, not a fixed height: a short result list does not force the
/// sheet to a tall empty box, matching `_SpaceEmojiSheet`'s own precedent.
const double _maxGridHeight = 340;

/// Opens the GIF picker as a sheet. [onPicked] runs after the sheet has
/// popped, the same convention `showEmojiPickerSheet` already uses, so a
/// caller re-focusing the composer is never fighting the closing route.
Future<void> showGifPickerSheet(
  BuildContext context, {
  required ValueChanged<api.Attachment> onPicked,
}) {
  return showAppSheet<void>(
    context,
    maxWidth: 480,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(child: _GifPickerBody(onPicked: onPicked)),
    ),
  );
}

/// The whole flow `composer.dart`'s own GIF button needs: open the sheet,
/// and once something is picked, fetch its bytes back once (`selectGif`
/// already stored them server side; this is only for the newly staged
/// tile's own local preview) and stage it - or hand [onError] a sentence,
/// never a raw exception, if that last step fails.
Future<void> pickGif({
  required BuildContext context,
  required WidgetRef ref,
  required AttachmentStagingController attachments,
  required ValueChanged<String?> onError,
}) {
  return showGifPickerSheet(
    context,
    onPicked: (attachment) async {
      try {
        final bytes = await ref
            .read(apiProvider)
            .fetchAttachment(attachment.id);
        // The composer may have been torn down while this awaited.
        if (!context.mounted) return;
        attachments.addResolved(attachment, bytes.bytes);
      } on api.ApiException catch (e) {
        onError(describeApiFailure('attach that gif', e));
      }
    },
  );
}

class _GifPickerBody extends ConsumerStatefulWidget {
  const _GifPickerBody({required this.onPicked});

  final ValueChanged<api.Attachment> onPicked;

  @override
  ConsumerState<_GifPickerBody> createState() => _GifPickerBodyState();
}

class _GifPickerBodyState extends ConsumerState<_GifPickerBody> {
  final _queryController = TextEditingController();
  Timer? _debounce;

  bool _loading = false;
  String? _error;
  List<api.GifResult>? _results;

  /// The result currently being picked, so its own tile can show a spinner
  /// and every other tile is disabled until this one resolves.
  String? _selectingId;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(_searchDebounce, () => unawaited(_search(query)));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ref.read(apiProvider).searchGifs(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure('search for gifs', e);
        _loading = false;
      });
    }
  }

  Future<void> _pick(api.GifResult result) async {
    setState(() {
      _selectingId = result.id;
      _error = null;
    });
    try {
      final attachment = await ref.read(apiProvider).selectGif(result.id);
      if (!mounted) return;
      final onPicked = widget.onPicked;
      Navigator.of(context).pop();
      onPicked(attachment);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = describeApiFailure('attach that gif', e);
        _selectingId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppInput(
            controller: _queryController,
            autofocus: true,
            placeholder: 'Search GIFs',
            icon: Icon(
              AppIcons.search,
              size: AppSizes.icon16,
              color: tokens.textSecondary,
            ),
            onChanged: _onQueryChanged,
            semanticLabel: 'Search GIFs',
          ),
          const SizedBox(height: AppSpacing.s12),
          if (_error != null) ...[
            AppErrorState(message: _error!),
            const SizedBox(height: AppSpacing.s12),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _maxGridHeight),
            child: _content(tokens),
          ),
        ],
      ),
    );
  }

  Widget _content(AppTokens tokens) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.s24),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final results = _results;
    if (results == null) {
      return Center(
        child: Text(
          'Type to search for a GIF.',
          style: AppText.body.copyWith(color: tokens.textSecondary),
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No matches.',
          style: AppText.body.copyWith(color: tokens.textSecondary),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        crossAxisSpacing: AppSpacing.s8,
        mainAxisSpacing: AppSpacing.s8,
        childAspectRatio: 1.3,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return _GifTile(
          result: result,
          busy: _selectingId != null,
          selecting: _selectingId == result.id,
          onTap: () => unawaited(_pick(result)),
        );
      },
    );
  }
}

class _GifTile extends ConsumerWidget {
  const _GifTile({
    required this.result,
    required this.busy,
    required this.selecting,
    required this.onTap,
  });

  final api.GifResult result;

  /// Whether *some* tile in the grid is currently being picked - every tile
  /// is disabled while that is true, not only the one selected.
  final bool busy;
  final bool selecting;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final preview = ref.watch(gifPreviewBytesProvider(result.id));
    return Semantics(
      button: true,
      label: result.title.isEmpty ? 'Pick a GIF' : 'Pick: ${result.title}',
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(AppRadii.control),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: ColoredBox(
            color: tokens.surfaceBase,
            child: Stack(
              fit: StackFit.expand,
              children: [
                switch (preview) {
                  AsyncData(value: final Uint8List bytes) => Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    cacheWidth: decodeEdge(context, 160),
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                  AsyncError() => const SizedBox.shrink(),
                  _ => const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                },
                if (selecting)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: tokens.surfaceBase.withValues(alpha: 0.65),
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
