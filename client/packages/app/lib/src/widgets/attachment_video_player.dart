// SPDX-License-Identifier: Apache-2.0
/// Inline playback for a `video/*` attachment: a real player in the
/// transcript rather than a name-and-size chip.
///
/// See `attachment_video_source.dart` for how each platform gets the
/// bearer-token-gated bytes to `package:media_kit`'s player, and
/// `attachment_save.dart` for the save action beside the player - a video
/// that plays but cannot be saved is still only half of what this fixes.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../providers/providers.dart';
import 'attachment_format.dart';
import 'attachment_save.dart';
import 'attachment_video_source_io.dart'
    if (dart.library.js_interop) 'attachment_video_source_web.dart';
import 'run_guarded.dart';

/// Half [kMessageColumnMax], the same cap an inline image draws under, and
/// the same 16:9 box every shipped platform's player fills as it loads
/// before the real video dimensions are known.
const double kInlineVideoMax = kMessageColumnMax;

class AttachmentVideoPlayer extends ConsumerStatefulWidget {
  const AttachmentVideoPlayer({super.key, required this.attachment});

  final api.Attachment attachment;

  @override
  ConsumerState<AttachmentVideoPlayer> createState() =>
      _AttachmentVideoPlayerState();
}

class _AttachmentVideoPlayerState extends ConsumerState<AttachmentVideoPlayer>
    with GuardedActionState<AttachmentVideoPlayer> {
  final Player _player = Player();
  late final VideoController _videoController = VideoController(_player);
  final _source = createAttachmentVideoSource();

  bool _ready = false;
  bool _saving = false;
  double? _fetchProgress;
  StreamSubscription<String>? _errorSub;

  api.Attachment get attachment => widget.attachment;

  @override
  void initState() {
    super.initState();
    // A decode failure mid-playback surfaces here rather than a thrown Future, since it can fire after open() already succeeded.
    _errorSub = _player.stream.error.listen((_) {
      if (mounted) setActionError('Could not play ${attachment.filename}.');
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    clearActionError();
    setState(() {
      _ready = false;
      _fetchProgress = null;
    });
    try {
      final media = await _source.open(
        apiClient: ref.read(apiProvider),
        attachment: attachment,
        onProgress: (progress) {
          if (mounted) setState(() => _fetchProgress = progress);
        },
      );
      if (!mounted) return;
      await _player.open(media, play: false);
      if (!mounted) return;
      setState(() => _ready = true);
    } on api.ApiException catch (e) {
      if (mounted) {
        setActionError(describeApiFailure('load ${attachment.filename}', e));
      }
    } catch (_) {
      if (mounted) setActionError('Could not load ${attachment.filename}.');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final failure = await saveAttachment(ref, attachment);
    if (!mounted) return;
    setState(() => _saving = false);
    if (failure != null) {
      setActionError(failure);
    } else {
      clearActionError();
    }
  }

  @override
  void dispose() {
    unawaited(_errorSub?.cancel());
    _player.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final caption =
        '${attachment.filename} · ${formatByteSize(attachment.size)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kInlineVideoMax),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.stripe,
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: _ready
                    ? Video(controller: _videoController)
                    : Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: _fetchProgress,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(color: tokens.textSecondary),
              ),
            ),
            const SizedBox(width: AppSpacing.s4),
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.s4),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : AppIconButton(
                    icon: AppIcons.download,
                    semanticLabel: 'Save ${attachment.filename}',
                    tooltip: 'Save',
                    size: AppIconButtonSize.sm,
                    onPressed: _save,
                  ),
          ],
        ),
        if (actionError != null) ...[
          const SizedBox(height: AppSpacing.s4),
          AppErrorState(
            message: actionError!,
            onRetry: _ready ? null : _load,
            onDismiss: clearActionError,
          ),
        ],
      ],
    );
  }
}
