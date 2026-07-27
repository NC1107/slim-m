// SPDX-License-Identifier: Apache-2.0
/// One of the deployment's own emoji, drawn from its image.
///
/// Square and sized by the caller, because an emoji stands in for a glyph:
/// wherever it appears it has to sit on the same line as the text around it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/emoji_catalog_provider.dart';

/// The emoji id a `:shortcode:` names, or null when [token] names none of the
/// deployment's own. [index] is `customEmojiIndexProvider`'s name-to-id map.
///
/// The one place that reads the colon delimiters back off a token, so a
/// message body and a reaction chip cannot drift apart about what resolves.
/// A miss is the normal case (most colon runs name nothing) and returns null
/// rather than throwing, which leaves the caller showing the text it had. It
/// judges the token alone: whether the text around one reads as an emoji at
/// all is the caller's, since only a message body has text around it.
String? customEmojiIdFor(String token, Map<String, String> index) {
  if (token.length < 3 || !token.startsWith(':') || !token.endsWith(':')) {
    return null;
  }
  return index[token.substring(1, token.length - 1).toLowerCase()];
}

class CustomEmojiImage extends ConsumerWidget {
  const CustomEmojiImage({
    super.key,
    required this.emojiId,
    this.label,
    this.size = 20,
  });

  final String emojiId;

  /// The `:shortcode:` this image stands for, read out in place of the
  /// picture, which no screen reader can describe. Null where an enclosing
  /// [Semantics] already names it, so it is not announced twice.
  final String? label;

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final bytes = ref.watch(customEmojiImageProvider(emojiId));
    final image = SizedBox(
      width: size,
      height: size,
      child: switch (bytes) {
        AsyncData(:final value) => Image.memory(
          value,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
        // A fetch that failed says so rather than leaving a tile that looks
        // tappable and blank; one still in flight just holds the space.
        AsyncError() => Icon(
          AppIcons.imageMissing,
          size: size,
          color: tokens.textSecondary,
        ),
        _ => const SizedBox.shrink(),
      },
    );
    final name = label;
    if (name == null) return image;
    return Semantics(label: name, image: true, child: image);
  }
}
