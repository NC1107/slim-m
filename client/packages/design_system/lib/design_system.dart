// SPDX-License-Identifier: Apache-2.0
/// slim-m design system: tokens, theme, and icon wrappers.
///
/// Widgets consume semantic tokens through `AppTokens`, never raw hex or
/// numeric literals, so a palette change touches a handful of values here
/// rather than every widget.
library;

export 'src/app_tokens.dart';
export 'src/app_icons.dart';
