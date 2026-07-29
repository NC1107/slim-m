// SPDX-License-Identifier: Apache-2.0
/// The two presentational pieces the transcript composes but that carry no
/// list logic of their own: the start-of-channel header, and the one-shot
/// entrance a freshly arrived message rides in on.
///
/// Split out of `message_transcript.dart` to keep that file to the reversed
/// scroll and the grouping, unread and day rules that decide what each row
/// shows.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/breakpoints.dart';

/// The block at the very top of a channel's history: a mark, the channel's
/// name, and its topic if it has one. It fills what would otherwise be a wide
/// empty band above a short conversation (the list is bottom-anchored), and is
/// the one place the channel topic is shown in the body.
class ChannelStartHeader extends StatelessWidget {
  const ChannelStartHeader({super.key, required this.name, this.topic});

  final String name;
  final String? topic;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // The message rows' own gutter, so the block left-aligns with them.
    final gutter = LayoutClass.of(context) == LayoutClass.compact
        ? AppSizes.paneGutterCompact
        : AppSizes.paneGutter;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        gutter,
        AppSpacing.s24,
        gutter,
        AppSpacing.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Icon(AppIcons.hash, size: 26, color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Welcome to #$name',
            style: AppText.title.copyWith(color: tokens.textPrimary),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            topic ?? 'This is the start of the #$name channel.',
            style: AppText.body.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// A one-shot fade-and-rise for a freshly arrived message. Keyed by the newest
/// id by its caller, so a new arrival remounts and plays while a rebuild with
/// the same id reuses the running animation rather than cutting it. Reads
/// reduce-motion once, on first layout, and lands instantly if set.
class MessageEntrance extends StatefulWidget {
  const MessageEntrance({
    super.key,
    required this.child,
    required this.animateOnMount,
  });

  final Widget child;
  final bool animateOnMount;

  @override
  State<MessageEntrance> createState() => _MessageEntranceState();
}

class _MessageEntranceState extends State<MessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.base,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animateOnMount && !AppMotion.isReduced(context)) {
      _controller.forward();
    } else {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final t = AppMotion.entrance.transform(_controller.value);
      return Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 8),
          child: child,
        ),
      );
    },
  );
}
