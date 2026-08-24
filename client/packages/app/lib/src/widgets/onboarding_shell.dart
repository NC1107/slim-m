// SPDX-License-Identifier: Apache-2.0
/// The frame every pre-session screen sits in: a brand panel on the left, the
/// step you are on to the right of it.
///
/// The shape is an installer's, deliberately. Getting into a self-hosted Space
/// is genuinely several decisions - which server, is it the right server, who
/// are you on it - and the previous single centred card gave no sense of how
/// many were left or which one you were in. A fixed panel plus a numbered
/// stepper answers both without a word of copy.
///
/// The panel is chrome, so it goes first when there is no room: below
/// [_panelFloor] it collapses to the mark and the wordmark above the content,
/// because a phone needs the whole width for the form and the pitch is not
/// what somebody halfway through signing in came for.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Narrowest width that still gets the brand panel. Above this there is room
/// for a 260px brand rail and a 440px form with gutters; below it, there is not.
const double _panelFloor = 900;

/// One step in the join flow, and how far along it the caller is.
///
/// Numbered rather than named-only because the number is the part that says
/// "two more after this", which is the whole reason the stepper is here.
///
/// Two members, not three: confirming a server's identity is a conditional
/// security check, not a counted step, since it fires once, more than once,
/// or not at all depending on what is already pinned for that address.
/// `server_fingerprint_step.dart` and `server_identity_changed_step.dart`
/// render it outside this shell for exactly that reason. An earlier third
/// member, `server`, was never passed by any production widget and is
/// removed rather than left dead.
enum OnboardingStep {
  invite('invite'),
  identity('who are you');

  const OnboardingStep(this.label);

  final String label;
}

class OnboardingShell extends StatelessWidget {
  const OnboardingShell({super.key, required this.child, this.step});

  final Widget child;

  /// The step being shown, or null for a screen that is not part of the join
  /// flow - signing back in to a server you already trust is one act, and a
  /// "step 1 of 1" would be furniture.
  final OnboardingStep? step;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final wide = MediaQuery.sizeOf(context).width >= _panelFloor;

    final content = Align(
      // Top-ish with room; centred on a phone, which has no height to spare.
      alignment: wide ? const Alignment(0, -0.55) : Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!wide) ...[
              const _Wordmark(compact: true),
              const SizedBox(height: AppSpacing.s24),
            ],
            Center(
              child: ConstrainedBox(
                // Wider than the form so the step labels have room.
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // A band, not a hard cut: sign-in grows this in place when "create account" opens.
                    AppRevealBand(
                      child: step == null
                          ? null
                          : Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.s32,
                              ),
                              child: OnboardingStepper(current: step!),
                            ),
                    ),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!wide) {
      return Scaffold(body: SafeArea(child: content));
    }

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Container(
              // A slim brand rail, not a third of the viewport; see [_BrandPanel].
              width: 260,
              decoration: BoxDecoration(
                color: tokens.surfaceSunken,
                border: Border(right: BorderSide(color: tokens.borderSubtle)),
              ),
              child: const _BrandPanel(),
            ),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

/// The mark beside the wordmark, in mono at the design's own tracking.
class _Wordmark extends StatelessWidget {
  const _Wordmark({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Row(
      mainAxisAlignment: compact
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        AppBrandMark(size: compact ? 24 : 30),
        const SizedBox(width: AppSpacing.s12),
        Text(
          'slim-m',
          style: AppText.heading.copyWith(
            color: tokens.textPrimary,
            fontFamily: AppFonts.mono,
            fontWeight: AppWeights.medium,
            letterSpacing: 20 * 0.04,
          ),
        ),
      ],
    );
  }
}

/// The left column: the mark, and room kept for whatever goes under it.
///
/// Deliberately blank below the wordmark. It carried a headline, a subtitle
/// and three promises, and most of it was either marketing or not true yet -
/// it advertised a shared canvas the product does not have. Copy that
/// overstates what a self-hosted server does is worse here than nowhere,
/// because this is the screen where somebody decides whether to trust one.
///
/// The layout is kept rather than collapsed so there is a place to put real
/// words when there are some - but the rail is narrow (its container's width),
/// because at a third of the viewport this emptiness read as an unfinished
/// half rather than a margin.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.s32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_Wordmark()],
    ),
  );
}

/// `1 invite - 2 who are you`.
///
/// Every step is always shown, including the ones behind you: the point is to
/// say how many there are, and a stepper that only counts forwards cannot.
/// Steps already passed are ticked rather than numbered, so "done" and "still
/// to come" differ in shape and not only in colour.
class OnboardingStepper extends StatelessWidget {
  const OnboardingStepper({super.key, required this.current});

  final OnboardingStep current;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final steps = OnboardingStep.values;

    return Semantics(
      container: true,
      label: 'Step ${current.index + 1} of ${steps.length}: ${current.label}',
      child: ExcludeSemantics(
        // Under ~420px only the current step keeps its words; the count stays.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelled = constraints.maxWidth >= 420;
            return Row(
              children: [
                for (final (i, step) in steps.indexed) ...[
                  // Fixed, not Expanded: stretching truncated the longest label.
                  if (i > 0)
                    Container(
                      width: 24,
                      height: 1,
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                      ),
                      color: tokens.borderSubtle,
                    ),
                  // Loose flex: flex 0 reads as non-flex and constrains nothing.
                  Flexible(
                    child: _Pip(
                      index: i,
                      label: labelled || step == current ? step.label : null,
                      done: i < current.index,
                      active: step == current,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Pip extends StatelessWidget {
  const _Pip({
    required this.index,
    required this.label,
    required this.done,
    required this.active,
  });

  final int index;

  /// Null where there is no room for words; the pip keeps its number.
  final String? label;

  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final lit = done || active;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? tokens.accentSoft : Colors.transparent,
            border: Border.all(
              color: lit ? tokens.accent : tokens.borderSubtle,
            ),
          ),
          child: done
              ? Icon(AppIcons.check, size: 11, color: tokens.accent)
              : Text(
                  '${index + 1}',
                  style: AppText.code.copyWith(
                    fontSize: AppText.micro.fontSize,
                    color: lit ? tokens.accent : tokens.textSecondary,
                  ),
                ),
        ),
        if (label != null) ...[
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label!,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(
                color: lit ? tokens.textPrimary : tokens.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// How a server's identity compares against whatever this app already
/// pinned for that address. Three states, not a boolean, because "no pin
/// exists yet" and "the pin does not match" are opposite risk levels and
/// must never share one rendering.
enum ServerIdentityStatus {
  /// The fetched key matches the pin. The tick is about this, and only
  /// this: reaching a server says who answered, not that it is the one
  /// trusted last time.
  confirmed,

  /// Nothing is pinned yet, or the server is too old to report an identity
  /// at all (`Version.identity == null`). Neither is a safety claim in
  /// either direction, so this renders as quietly as an unasked question.
  unknown,

  /// The fetched key does not match the pin. Must read louder than
  /// [unknown] and never as a neutral absence of information: this is the
  /// one state trust-on-first-use exists to make visible.
  mismatch,
}

/// The Space a form is about: its initials, its name and its host, with a
/// glyph for how its identity compares against what this app already
/// pinned.
///
/// Shown only once `/version` has answered, because until then the only
/// honest thing to say about a typed address is nothing.
class ServerIdentityChip extends StatelessWidget {
  const ServerIdentityChip({
    super.key,
    required this.spaceName,
    required this.host,
    this.status = ServerIdentityStatus.unknown,
  });

  final String spaceName;
  final String host;
  final ServerIdentityStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final stripped = initialsFor(spaceName);
    final initials = stripped.isEmpty ? '?' : stripped;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s16),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surfaceSunken,
              border: Border.all(color: tokens.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Text(
              initials,
              style: AppText.code.copyWith(
                fontSize: 11,
                color: tokens.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: spaceName,
                    style: TextStyle(color: tokens.textPrimary),
                  ),
                  TextSpan(
                    text: '  $host',
                    style: AppText.code.copyWith(
                      fontSize: 12,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
              style: AppText.caption,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.s8),
          _IdentityStatusGlyph(status: status),
        ],
      ),
    );
  }
}

/// The tick, its louder mismatch counterpart, or nothing - each with a
/// visible word beside it, not only a screen-reader label.
///
/// This is a security-relevant signal (trust-on-first-use's one visible
/// cue for whether a server is the one trusted last time), so a sighted,
/// non-screen-reader user needs on-screen words for it too, not just a
/// tooltip nobody has a reason to hover a 16px glyph for. The full
/// semantic sentence stays on the [Semantics] wrapper for a screen reader;
/// the short visible word is `excludeSemantics`-scoped so nothing is
/// announced twice.
class _IdentityStatusGlyph extends StatelessWidget {
  const _IdentityStatusGlyph({required this.status});

  final ServerIdentityStatus status;

  static const _labels = {
    ServerIdentityStatus.confirmed:
        'Identity confirmed: matches the key this app pinned before.',
    ServerIdentityStatus.unknown: 'Identity not yet confirmed.',
    ServerIdentityStatus.mismatch:
        "Identity does not match the key this app pinned before. This "
        'server may not be the one trusted last time.',
  };

  /// The short visible word beside the glyph. Unknown renders neither an
  /// icon nor a word, deliberately: it is not yet a claim in either
  /// direction, so it stays as quiet as an unasked question.
  static const _visibleText = {
    ServerIdentityStatus.confirmed: 'Confirmed',
    ServerIdentityStatus.mismatch: 'Changed',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final (icon, color) = switch (status) {
      ServerIdentityStatus.confirmed => (AppIcons.check, tokens.accent),
      ServerIdentityStatus.unknown => (null, null),
      ServerIdentityStatus.mismatch => (AppIcons.danger, tokens.dangerText),
    };
    final text = _visibleText[status];

    return Semantics(
      label: _labels[status],
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppSizes.icon16,
            height: AppSizes.icon16,
            child: icon == null
                ? null
                : Icon(icon, size: AppSizes.icon16, color: color),
          ),
          if (text != null) ...[
            const SizedBox(width: AppSpacing.s4),
            Text(
              text,
              style: AppText.caption.copyWith(
                color: color,
                fontWeight: AppWeights.semi,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
