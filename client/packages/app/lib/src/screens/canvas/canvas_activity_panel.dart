// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The activity log's presentation: a navigable list plus an always-mounted
/// live region. Split from `canvas_pane_body.dart` because this is the one
/// place canvas widgets resolve an actor id into a display name, the same
/// job `_cursorLabel` already does for a remote pointer in `canvas_pane.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../providers/user_profiles.dart';
import '../../widgets/author_label.dart';
import 'canvas_activity_log.dart';

/// Renders nothing visible, but its `Semantics` label changes on every
/// throttled batch - the one thing a screen reader needs to announce canvas
/// activity without anyone having opened [CanvasActivityPanel] at all.
///
/// Mounted unconditionally by `CanvasPaneBody`, so a burst of changes still
/// announces while the panel is closed; a repeated identical summary is a
/// known platform limitation this does not try to work around, since the
/// only fix (an invisible varying suffix) would corrupt what is literally
/// read aloud.
class CanvasActivityAnnouncer extends ConsumerStatefulWidget {
  const CanvasActivityAnnouncer({super.key, required this.activityLog});

  final CanvasActivityLog activityLog;

  /// Exposed so a test can find this exact node rather than any other
  /// `Semantics` widget an ancestor happens to build.
  static const Key liveRegionKey = Key('canvas_activity_announcer_region');

  @override
  ConsumerState<CanvasActivityAnnouncer> createState() =>
      _CanvasActivityAnnouncerState();
}

class _CanvasActivityAnnouncerState
    extends ConsumerState<CanvasActivityAnnouncer> {
  String _text = '';
  int _lastTick = 0;

  @override
  void initState() {
    super.initState();
    widget.activityLog.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant CanvasActivityAnnouncer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.activityLog, widget.activityLog)) return;
    oldWidget.activityLog.removeListener(_onChange);
    widget.activityLog.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.activityLog.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final tick = widget.activityLog.announcementTick;
    if (tick == _lastTick) return;
    _lastTick = tick;
    final batch = widget.activityLog.takeAnnouncementBatch();
    if (batch.isEmpty) return;
    final text = summarizeCanvasActivity(batch, nameFor: _nameFor);
    if (mounted) setState(() => _text = text);
  }

  String? _nameFor(String userId) {
    final profiles = ref.read(batchProfilesControllerProvider);
    resolveAuthorProfiles(ref, [userId]);
    return profiles[userId]?.displayName;
  }

  @override
  Widget build(BuildContext context) => Semantics(
    key: CanvasActivityAnnouncer.liveRegionKey,
    liveRegion: true,
    label: _text,
    child: const SizedBox.shrink(),
  );
}

/// A full-height, navigable substitute for the canvas surface: a summary of
/// what is currently on the canvas, followed by a list of what changed,
/// newest first. Every row carries a full sentence, both as its own
/// `Semantics` label and as ordinary visible text - a cue is never carried
/// by one channel alone anywhere else in this product, and this is no
/// exception.
class CanvasActivityPanel extends StatelessWidget {
  const CanvasActivityPanel({
    super.key,
    required this.activityLog,
    required this.summary,
    required this.objectCount,
  });

  final CanvasActivityLog activityLog;

  /// "N objects on this canvas: X strokes, Y images" - computed by the
  /// caller from the live document, since this log only ever tracks changes,
  /// never the canvas's total current contents.
  final String summary;

  /// [summary]'s own headline number, passed separately rather than parsed
  /// back out of it: what decides whether an empty log gets its own
  /// clarifying line below, since a nonzero count above an apparently-empty
  /// history otherwise reads as a contradiction - the canvas has content,
  /// but the log that tracks how it got there shows nothing, when what is
  /// really true is that the content predates this session's own log (a
  /// catch-up gap, or ops aged past retention).
  final int objectCount;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return AnimatedBuilder(
      animation: activityLog,
      builder: (context, _) {
        final entries = activityLog.entries.reversed.toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s12),
              child: Semantics(
                container: true,
                header: true,
                child: Text(
                  summary,
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s24,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No canvas activity yet.',
                              style: AppText.body.copyWith(
                                color: tokens.textSecondary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (objectCount > 0) ...[
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                "Activity from before you joined isn't "
                                'shown here.',
                                style: AppText.caption.copyWith(
                                  color: tokens.textDisabled,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, index) =>
                          _ActivityRow(entry: entries[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ActivityRow extends ConsumerWidget {
  const _ActivityRow({required this.entry});

  final CanvasActivityEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actorId = entry.actorId;
    String? name;
    if (actorId != null) {
      final profiles = ref.watch(batchProfilesControllerProvider);
      resolveAuthorProfiles(ref, [actorId]);
      name = authorLabel(
        authorId: actorId,
        cachedDisplayName: null,
        profiles: profiles,
      );
    }
    final text = describeCanvasActivityEntry(entry, nameFor: (_) => name);
    // AppListRow: the same focusable row the channel rail already uses.
    return AppListRow(label: text, meta: _relativeTime(entry.at));
  }
}

/// A short, relative timestamp ("just now", "5m ago"). `AppListRow` merges
/// its own `meta` text into the row's single `Semantics` label alongside
/// the sentence - confirmed against the real dumped tree, not assumed - so
/// a screen reader hears both rather than only the visible one.
String _relativeTime(DateTime at) {
  final elapsed = DateTime.now().difference(at);
  if (elapsed.inSeconds < 30) return 'just now';
  if (elapsed.inMinutes < 1) return '${elapsed.inSeconds}s ago';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}
