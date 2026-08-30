// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The compact quote a reply shows above its own row: the parent's author
/// and a one-line snippet of its content, tappable to jump to it.
///
/// Deliberately resolves nothing itself. The parent's content, author and
/// liveness all come from [ReplyQuote.resolved], which the transcript
/// already looked up against whatever it currently has loaded - and that
/// lookup is where blocking and deletion are already handled, so this
/// widget cannot leak either: a blocked author's message is absent from it
/// exactly as it is absent from its own row, and a deleted message was
/// discarded from the local store entirely rather than merely marked. Both
/// causes, and a parent simply not paged in yet, collapse into the same
/// null and the same honest placeholder - never a guess at which one it was.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/user_profiles.dart';
import 'author_label.dart';

/// How much of a quoted message's own text is shown before it is cut off - a
/// compact quote, not a second copy of the message.
const int _quoteMaxRunes = 120;

class ReplyQuote extends ConsumerWidget {
  const ReplyQuote({super.key, required this.resolved, required this.onTap});

  /// The parent message, if this client currently holds it locally. See this
  /// file's own doc comment for what null does and does not mean.
  final Message? resolved;

  /// Jumps to the parent. Wired even when [resolved] is null: the
  /// transcript's own loaded window is not the only place a message can be
  /// found, and the jump this calls pages further history in on its own.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final resolved = this.resolved;
    final label = resolved == null
        ? null
        : authorLabelResolved(
            authorId: resolved.authorId,
            cachedDisplayName: resolved.authorDisplayName,
            resolution: ref.watch(
              batchProfilesControllerProvider.select(
                (m) => authorResolution(m, resolved.authorId ?? ''),
              ),
            ),
          );
    final snippet = resolved == null
        ? 'Message unavailable'
        : _snippet(resolved.content);
    final textStyle = AppText.caption.copyWith(
      color: tokens.textSecondary,
      fontStyle: resolved == null ? FontStyle.italic : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Semantics(
        button: true,
        label: label == null
            ? 'Reply to a message that is not available'
            : 'Reply to $label: $snippet',
        child: AppFocusRing(
          radius: AppRadii.control,
          builder: (context, onFocusChange) => InkWell(
            onTap: onTap,
            // AppFocusRing replaces this overlay; see its own doc comment.
            focusColor: Colors.transparent,
            onFocusChange: onFocusChange,
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.reply, size: 13, color: tokens.textSecondary),
                const SizedBox(width: AppSpacing.s4),
                // One Flexible for both spans: a long display name alone would overflow the row otherwise.
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      style: textStyle,
                      children: [
                        if (label != null)
                          TextSpan(
                            text: '$label  ',
                            style: const TextStyle(fontWeight: AppWeights.semi),
                          ),
                        TextSpan(text: snippet),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// A one-line, rune-safe truncation - `String.substring` cuts mid-surrogate
/// on a codepoint outside the BMP, which a plain-text preview should not risk.
String _snippet(String content) {
  final oneLine = content.replaceAll('\n', ' ').trim();
  if (oneLine.isEmpty) return '(no text)';
  final runes = oneLine.runes.toList(growable: false);
  if (runes.length <= _quoteMaxRunes) return oneLine;
  return '${String.fromCharCodes(runes.take(_quoteMaxRunes))}…';
}
