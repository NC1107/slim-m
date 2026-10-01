// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Puts the caret in the [Composer] below it for a pane the user opened on
/// purpose (the docked thread), and again on a thread switch or when the open
/// thread is asked for once more. Never used where it would raise a phone's
/// keyboard unasked.
///
/// The node is found in this subtree rather than taken from
/// [composerFocusNodeProvider]: that registry holds whichever composer mounted
/// last, which with a channel composer beside the pane is not always this one.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/threads.dart';

class ComposerAutofocus extends ConsumerStatefulWidget {
  const ComposerAutofocus({
    super.key,
    required this.channelId,
    required this.child,
  });

  final String channelId;
  final Widget child;

  @override
  ConsumerState<ComposerAutofocus> createState() => _ComposerAutofocusState();
}

class _ComposerAutofocusState extends ConsumerState<ComposerAutofocus> {
  @override
  void initState() {
    super.initState();
    _focusAfterFrame();
    ref.listenManual(
      threadComposerFocusRequestProvider,
      (_, _) => _focusComposer(),
    );
  }

  @override
  void didUpdateWidget(ComposerAutofocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channelId != widget.channelId) _focusAfterFrame();
  }

  void _focusAfterFrame() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusComposer());

  void _focusComposer() {
    if (!mounted) return;
    FocusNode? node;
    void visit(Element element) {
      if (node != null) return;
      final widget = element.widget;
      if (widget is EditableText) {
        node = widget.focusNode;
      } else {
        element.visitChildren(visit);
      }
    }

    (context as Element).visitChildren(visit);
    node?.requestFocus();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
