// SPDX-License-Identifier: Apache-2.0
//
// Design-token WCAG 2.1 contrast gate for slim-m.
//
// Computes WCAG 2.1 relative-luminance contrast ratios for the meaningful
// foreground/background token pairs in client/packages/design_system and
// checks each against the WCAG 2.1 AA minimum for its usage:
//   - normal (body) text                          4.5:1
//   - large text, icons, and non-text UI (borders) 3:1
//
// Usage:
//   node scripts/check-contrast.mjs
//
// Prints a table of every pair with its computed ratio, required minimum,
// and PASS/FAIL, then exits non-zero if any pair fails.
//
// Some pairs are marked "provisional" below. These are known, tracked design
// issues (see docs/ROADMAP.md): the border-subtle color and the light-theme
// accent used as body text were picked before the contrast gate existed and
// are not yet signed off. Provisional pairs are still checked against the
// real WCAG minimum and still affect the exit code; the flag only adds a
// note in the output so they are triaged deliberately instead of silently
// passing or silently failing unnoticed.
//
// Update TOKENS below whenever
// client/packages/design_system/lib/src/app_tokens.dart changes.

const TOKENS = {
  light: {
    surfaceBase: '#F7F8F9',
    surfaceRaised: '#FFFFFF',
    borderSubtle: '#DCE0E5',
    textPrimary: '#1B1E22',
    textSecondary: '#5B6169',
    accent: '#1E7F77',
  },
  dark: {
    surfaceBase: '#17191C',
    surfaceRaised: '#1F2226',
    borderSubtle: '#2E333A',
    textPrimary: '#ECEDEF',
    textSecondary: '#A7AEB6',
    accent: '#4FBDB4',
  },
};

const AA_NORMAL_TEXT = 4.5;
const AA_LARGE_TEXT_OR_UI = 3.0;

function hexToRgb(hex) {
  const clean = hex.replace('#', '');
  const n = parseInt(clean, 16);
  return {
    r: (n >> 16) & 255,
    g: (n >> 8) & 255,
    b: n & 255,
  };
}

// WCAG 2.1 relative luminance (https://www.w3.org/TR/WCAG21/#dfn-relative-luminance).
function channelToLinear(c) {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}

function relativeLuminance(hex) {
  const { r, g, b } = hexToRgb(hex);
  return 0.2126 * channelToLinear(r) + 0.7152 * channelToLinear(g) + 0.0722 * channelToLinear(b);
}

// WCAG 2.1 contrast ratio (https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio).
function contrastRatio(hexA, hexB) {
  const la = relativeLuminance(hexA);
  const lb = relativeLuminance(hexB);
  const lighter = Math.max(la, lb);
  const darker = Math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

function buildPairs() {
  const pairs = [];

  for (const theme of ['light', 'dark']) {
    const t = TOKENS[theme];
    const surfaces = ['surfaceBase', 'surfaceRaised'];

    for (const fg of ['textPrimary', 'textSecondary']) {
      for (const bg of surfaces) {
        pairs.push({
          theme,
          usage: `${fg} on ${bg}`,
          fgHex: t[fg],
          bgHex: t[bg],
          minRatio: AA_NORMAL_TEXT,
          provisional: false,
        });
      }
    }

    for (const bg of surfaces) {
      pairs.push({
        theme,
        usage: `accent (body text) on ${bg}`,
        fgHex: t.accent,
        bgHex: t[bg],
        minRatio: AA_NORMAL_TEXT,
        // Known-provisional: the light-theme accent used as body text has
        // not had design sign-off; see docs/ROADMAP.md.
        provisional: theme === 'light',
      });

      pairs.push({
        theme,
        usage: `accent (large text / icon) on ${bg}`,
        fgHex: t.accent,
        bgHex: t[bg],
        minRatio: AA_LARGE_TEXT_OR_UI,
        provisional: false,
      });
    }

    for (const bg of surfaces) {
      pairs.push({
        theme,
        usage: `borderSubtle on ${bg}`,
        fgHex: t.borderSubtle,
        bgHex: t[bg],
        minRatio: AA_LARGE_TEXT_OR_UI,
        // Known-provisional: borderSubtle was chosen for visual subtlety
        // before the contrast gate existed and is not yet signed off;
        // see docs/ROADMAP.md.
        provisional: true,
      });
    }
  }

  return pairs;
}

function formatRatio(r) {
  return `${r.toFixed(2)}:1`;
}

function pad(str, len) {
  return str.length >= len ? `${str} ` : str + ' '.repeat(len - str.length);
}

function main() {
  const results = buildPairs().map((p) => {
    const ratio = contrastRatio(p.fgHex, p.bgHex);
    return { ...p, ratio, pass: ratio >= p.minRatio };
  });

  const cols = { theme: 6, usage: 46, fg: 9, bg: 9, ratio: 8, min: 8, status: 7 };

  const header =
    pad('Theme', cols.theme) +
    pad('Pair', cols.usage) +
    pad('Fg', cols.fg) +
    pad('Bg', cols.bg) +
    pad('Ratio', cols.ratio) +
    pad('Min', cols.min) +
    pad('Status', cols.status) +
    'Flag';
  const rule = '-'.repeat(header.length + 12);

  console.log(header);
  console.log(rule);

  for (const r of results) {
    console.log(
      pad(r.theme, cols.theme) +
        pad(r.usage, cols.usage) +
        pad(r.fgHex, cols.fg) +
        pad(r.bgHex, cols.bg) +
        pad(formatRatio(r.ratio), cols.ratio) +
        pad(formatRatio(r.minRatio), cols.min) +
        pad(r.pass ? 'PASS' : 'FAIL', cols.status) +
        (r.provisional ? 'PROVISIONAL' : ''),
    );
  }

  const failures = results.filter((r) => !r.pass);
  const provisionalFailures = failures.filter((r) => r.provisional);
  const unexpectedFailures = failures.filter((r) => !r.provisional);

  console.log('');
  console.log(`Total pairs checked: ${results.length}`);
  console.log(`Passing: ${results.length - failures.length}`);
  console.log(
    `Failing: ${failures.length} (${provisionalFailures.length} known-provisional, ${unexpectedFailures.length} unexpected)`,
  );

  if (failures.length > 0) {
    console.log('');
    console.log('Failing pairs:');
    for (const r of failures) {
      const tag = r.provisional ? '[known-provisional]' : '[UNEXPECTED]';
      console.log(
        `  ${tag} ${r.theme} ${r.usage}: ${formatRatio(r.ratio)} (needs ${formatRatio(r.minRatio)})`,
      );
    }
  }

  if (unexpectedFailures.length > 0) {
    console.log('');
    console.log(
      'One or more pairs failed that are NOT on the known-provisional list. Treat this as a regression, not a triage item.',
    );
  }

  if (failures.length > 0) {
    process.exitCode = 1;
  }
}

main();
