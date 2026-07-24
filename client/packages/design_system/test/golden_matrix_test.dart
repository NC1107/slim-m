// SPDX-License-Identifier: Apache-2.0
/// The golden matrix: every theme at 100% and 200% text scale.
///
/// The layout assertions (no overflow at any scale) run everywhere and are the
/// part that catches real regressions.
///
/// The pixel comparison is gated behind SLIMM_GOLDENS=1 and its reference images
/// are deliberately NOT committed yet. Skia and font rendering differ between
/// machines, so images generated on a contributor's box would never match CI's
/// runner, and committing them would mean a permanently red build that everyone
/// learns to ignore. Generate them on the CI runner
/// (`flutter test --update-goldens`), commit those, then enable the flag there.
///
/// What these actually guard is the thing that breaks silently: text at 200%
/// overflowing its container. A layout that looks right at 100% and clips at
/// 200% is a real accessibility failure, and only a rendered comparison catches
/// it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

/// The themes the matrix covers.
const _themes = <String, AppTokens>{
  'light': AppTokens.light,
  'dark': AppTokens.dark,
  'true_black': AppTokens.trueBlack,
};

/// Text scales. 2.0 is the accessibility ceiling the roadmap commits to.
const _scales = <String, double>{'100': 1.0, '200': 2.0};

/// A representative slice of chrome: a header, a selected and unselected row,
/// and a body message. Enough surface that a token or spacing regression shows
/// up, without pulling in the whole app and its providers.
Widget _sample(AppTokens tokens) {
  return Builder(
    builder: (context) {
      return Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 52,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
              ),
              child: Text(
                'slim-m',
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
              color: tokens.accent.withValues(alpha: 0.12),
              child: Row(
                children: [
                  Icon(AppIcons.hash, size: 16, color: tokens.accent),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Text(
                      'general',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
              child: Row(
                children: [
                  Icon(AppIcons.voice, size: 16, color: tokens.textSecondary),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Text(
                      'lounge',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ada',
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'A short message, long enough to wrap once.',
                      style: TextStyle(color: tokens.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

void main() {
  for (final theme in _themes.entries) {
    for (final scale in _scales.entries) {
      testWidgets('${theme.key} at ${scale.key} percent', (tester) async {
        tester.view.physicalSize = const Size(800, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale.value)),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: buildTheme(
                theme.key == 'light' ? Brightness.light : Brightness.dark,
                theme.value,
              ),
              home: _sample(theme.value),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // No overflow at any scale. This is the assertion that matters most:
        // clipped text at 200% is an accessibility failure, and it is invisible
        // in a 100% screenshot.
        expect(tester.takeException(), isNull);

        // Pixel comparison only where the reference images were produced.
        if (const bool.fromEnvironment('SLIMM_GOLDENS')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/${theme.key}_${scale.key}.png'),
          );
        }
      });
    }
  }

  test('true black is genuinely black, not just dark', () {
    // The point of the OLED theme is the unlit pixel; anything above zero
    // defeats it, so this is worth asserting rather than eyeballing.
    expect(AppTokens.trueBlack.surfaceBase, const Color(0xFF000000));
    expect(
      AppTokens.trueBlack.surfaceBase.computeLuminance(),
      0.0,
      reason: 'a true-black base must emit no light',
    );
  });
}
