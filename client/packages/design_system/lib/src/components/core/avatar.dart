// SPDX-License-Identifier: Apache-2.0
/// The user picture: round for a person, square for a non-human author (a
/// webhook, a CI bot).
///
/// A round avatar gets a generated tint from a closed six-colour list and
/// mono initials; a square one gets none of that; the shape difference is
/// what marks a non-human author, since it survives a screenshot the way a
/// colour convention alone would not.
library;

import 'package:flutter/material.dart';

import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';
import 'status_dot.dart';

/// [circle] is the default, for a person. [square] marks a non-human
/// author.
enum AppAvatarShape { circle, square }

/// The closed six-colour set a round avatar's tint is hashed from. Kept
/// local rather than added to [AppTokens] (which already has a comparable
/// closed set in `AppCanvasColors.cursors`) because token values are gated
/// behind a design review this port does not have standing to reopen; see
/// the design-system notes for this file.
const List<Color> _avatarTints = [
  Color(0xFF4E6B66),
  Color(0xFF5C6E7A),
  Color(0xFF6A5B6E),
  Color(0xFF59685C),
  Color(0xFF6A6152),
  Color(0xFF4F5B66),
];

Color _tintFor(String name) {
  var n = 0;
  for (final unit in name.codeUnits) {
    n = (n + unit) % _avatarTints.length;
  }
  return _avatarTints[n];
}

/// Alphanumeric characters only, first two, uppercased. Not "first letter of
/// first and last word": a punctuation-stripped prefix is what the source
/// design actually does, and porting a friendlier-looking guess instead would
/// mean the same person's initials differ between this port and the rest of
/// the product.
String _initialsFor(String name) {
  final stripped = name.replaceAll(RegExp('[^a-zA-Z0-9]'), '');
  final take = stripped.length < 2 ? stripped.length : 2;
  return stripped.substring(0, take).toUpperCase();
}

double _atLeast9(double value) {
  final rounded = value.round();
  return rounded < 9 ? 9.0 : rounded.toDouble();
}

/// A light ink for the fixed, non-theme-swapped tint colours above. None of
/// [AppTokens]'s existing text colours fit: they all invert with theme, and
/// these tints do not, so [AppTokens.accentOn] would go illegible in dark and
/// true-black themes even though it is correct in light. Flagged as a gap
/// rather than reused.
const Color _avatarTintInk = Color(0xFFFFFFFF);

/// A person's (or bot's) picture, falling back to a tinted initials disc (or,
/// for a square avatar, to [placeholder]) when [image] is null or fails to
/// load.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.image,
    this.size = 36,
    this.shape = AppAvatarShape.circle,
    this.status,
    this.speaking = false,
    this.ringColor,
    this.placeholder,
    this.semanticLabel,
  });

  /// The display name a round avatar's tint and initials are derived from,
  /// and the fallback accessible label.
  final String name;
  final ImageProvider? image;

  /// Diameter. Avatars appear at several sizes across the app (a message
  /// row, a member list, a full profile), so this is a plain double.
  final double size;
  final AppAvatarShape shape;

  /// Presence overlay, drawn bottom-right. Composes [AppStatusDot] rather
  /// than duplicating its shape-per-state drawing.
  final AppPresence? status;

  /// A live-speaking ring. Takes priority over [ringColor], matching the
  /// source design's own precedence.
  final bool speaking;

  /// A caller-supplied ring (a fingerprint-confirmation colour strip, for
  /// instance), drawn when [speaking] is false.
  final Color? ringColor;

  /// Content for a [AppAvatarShape.square] avatar with no [image]: a square
  /// avatar never shows generated initials, since a bot's identity is its
  /// icon, not a name hash.
  final Widget? placeholder;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final round = shape == AppAvatarShape.circle;
    final radius = round ? size / 2 : AppRadii.control;
    final initials = round ? _initialsFor(name) : '';

    Widget content = image == null
        ? _Face(
            round: round,
            initials: initials,
            tokens: tokens,
            size: size,
            name: name,
            placeholder: placeholder)
        : Image(
            image: image!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => _Face(
              round: round,
              initials: initials,
              tokens: tokens,
              size: size,
              name: name,
              placeholder: placeholder,
            ),
          );

    content = SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(radius), child: content),
    );

    // A ring is drawn as a foreground overlay (like a CSS box-shadow) rather
    // than a bordered wrapper, so it never changes the avatar's own layout size.
    final ring = speaking ? tokens.accentFill : ringColor;
    if (ring != null) {
      content = Container(
        foregroundDecoration: BoxDecoration(
          shape: round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: round ? null : BorderRadius.circular(radius),
          border: Border.all(color: ring, width: 2),
        ),
        child: content,
      );
    }

    final presence = status;
    if (presence != null) {
      final dotSize = _atLeast9(size * 0.3);
      content = SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                    color: tokens.surfaceBase, shape: BoxShape.circle),
                child: AppStatusDot(
                    status: presence,
                    size: dotSize,
                    backgroundColor: tokens.surfaceBase),
              ),
            ),
          ],
        ),
      );
    }

    // ExcludeSemantics keeps the generated initials text (or a supplied
    // placeholder icon) from merging its own auto-label into this one.
    return Semantics(
      image: true,
      label: semanticLabel ?? name,
      child: ExcludeSemantics(child: content),
    );
  }
}

class _Face extends StatelessWidget {
  const _Face({
    required this.round,
    required this.initials,
    required this.tokens,
    required this.size,
    required this.name,
    required this.placeholder,
  });

  final bool round;
  final String initials;
  final AppTokens tokens;
  final double size;
  final String name;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context) {
    if (!round) {
      return DecoratedBox(
        decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            border: Border.all(color: tokens.borderSubtle)),
        child: Center(child: placeholder),
      );
    }

    final fontSize = _atLeast9(size * 0.36);
    return ColoredBox(
      color: _tintFor(name),
      child: Center(
        child: initials.isEmpty
            ? null
            : Text(
                initials,
                style: TextStyle(
                  fontFamily: AppFonts.mono,
                  fontSize: fontSize,
                  fontWeight: AppWeights.semi,
                  color: _avatarTintInk,
                ),
              ),
      ),
    );
  }
}
