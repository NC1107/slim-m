// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Turns a standard `:shortcode:` back into its codepoint.
library;

import 'package:emojis/emoji.dart';

/// The codepoint a standard emoji's `:shortcode:` names, or null for any other token.
///
/// The server keys a reaction on whatever string a client sent, so an API caller or bot
/// that sent `:anger:` left a key the picker itself never produces.
String? standardEmojiFor(String token) {
  if (token.length < 3 || !token.startsWith(':') || !token.endsWith(':')) {
    return null;
  }
  final name = token.substring(1, token.length - 1).toLowerCase();
  return Emoji.byShortName(name)?.char;
}
