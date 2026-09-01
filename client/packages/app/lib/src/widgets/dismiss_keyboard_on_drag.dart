// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Gives the keyboard's screen room back when somebody scrolls a list to read
/// it, and never when the list scrolls itself.
///
/// A phone's keyboard covers roughly half the transcript, so scrolling back
/// through a conversation while it is up means reading through a slot. The
/// tap-to-dismiss the channel already had only helps somebody who thinks to
/// tap; going looking through the history is the moment the room is wanted.
///
/// **Only a person's own drag counts.** A transcript scrolls itself constantly
/// - a message arrives and it follows, a jump lands on a search result - and
/// closing the composer under someone mid-sentence because somebody else
/// posted would be worse than never closing it at all. `dragDetails` is the
/// one thing separating the two: it is set by a drag activity and null for
/// every programmatic scroll.
///
/// A widget rather than a few lines inline in the pane so the behaviour is
/// testable as itself. Wrapped inline, the only honest test would have had to
/// stand up the whole channel screen, and a harness that reproduced the
/// listener instead would pass whatever the pane later did.
///
/// Not [ScrollViewKeyboardDismissBehavior.onDrag]: that is set on a scroll
/// view, and `message_transcript.dart` sits at the file-budget ceiling, but
/// more to the point it does not draw this distinction - it dismisses on any
/// drag the scrollable sees, without asking whose it was.
library;

import 'package:flutter/material.dart';

class DismissKeyboardOnDrag extends StatelessWidget {
  const DismissKeyboardOnDrag({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (notification.dragDetails != null) {
          FocusScope.of(context).unfocus();
        }
        // Never swallowed: the jump-to-latest pill watches these same notifications.
        return false;
      },
      child: child,
    );
  }
}
