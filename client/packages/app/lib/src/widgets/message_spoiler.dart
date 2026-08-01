// SPDX-License-Identifier: Apache-2.0
/// A `||spoiler||` span: a filled bar that swaps for its text on tap.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Deliberately this simple rather than an animated reveal: Discord's own
/// affordance for a spoiler is exactly a tap toggle, nothing more.
class MessageSpoiler extends StatefulWidget {
  const MessageSpoiler({super.key, required this.style, required this.spans});

  final TextStyle style;
  final List<InlineSpan> spans;

  @override
  State<MessageSpoiler> createState() => _MessageSpoilerState();
}

class _MessageSpoilerState extends State<MessageSpoiler> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return GestureDetector(
      onTap: () => setState(() => _revealed = !_revealed),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Kept in the tree (sizes the bar) but hidden from assistive tech until shown.
          ExcludeSemantics(
            excluding: !_revealed,
            child: Opacity(
              opacity: _revealed ? 1 : 0,
              child: Text.rich(
                TextSpan(style: widget.style, children: widget.spans),
              ),
            ),
          ),
          if (!_revealed)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.textPrimary,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
