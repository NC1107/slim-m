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
/// for a 380px panel and a 440px form with gutters; below it, there is not.
const double _panelFloor = 900;

/// One step in the join flow, and how far along it the caller is.
///
/// Numbered rather than named-only because the number is the part that says
/// "two more after this", which is the whole reason the stepper is here.
enum OnboardingStep {
  invite('invite'),
  server('confirm the server'),
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
      // Top-ish with room, so the form sits where the eye starts rather than
      // floating mid-pane; centred on a phone, which has no height to spare.
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
                // Wider than the 440 the form wants, so the three step labels
                // have room; the form itself stays 440 inside it.
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (step != null) ...[
                      OnboardingStepper(current: step!),
                      const SizedBox(height: AppSpacing.s32),
                    ],
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
              width: 380,
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

/// What this thing is, in the words the product already uses about itself.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static final _promises = <(IconData, String, String)>[
    (
      AppIcons.shield,
      'Nothing goes through us.',
      'Your account and your messages only ever reach the server you pick.',
    ),
    (
      AppIcons.members,
      'One server is one community.',
      'No feed, no recommendations, nobody else to find.',
    ),
    (AppIcons.code, 'Open source.', 'Read it, fork it, run your own.'),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Wordmark(),
          const SizedBox(height: AppSpacing.s32),
          Text(
            'A place for one group of friends. Nothing else.',
            style: AppText.title.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
              height: 1.15,
            ),
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Text, voice, screen share and a shared canvas, on a server '
            'one of you owns.',
            style: AppText.body.copyWith(
              color: tokens.textSecondary,
              height: 1.5,
            ),
          ),
          const Spacer(),
          for (final (icon, title, detail) in _promises)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      icon,
                      size: AppSizes.icon16,
                      color: tokens.accent,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '$title ',
                            style: TextStyle(
                              color: tokens.textPrimary,
                              fontWeight: AppWeights.medium,
                            ),
                          ),
                          TextSpan(
                            text: detail,
                            style: TextStyle(color: tokens.textSecondary),
                          ),
                        ],
                      ),
                      style: AppText.caption.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// `1 invite - 2 confirm the server - 3 who are you`.
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
        // Every label together needs about 420px. Below that only the step you
        // are on keeps its words; the count is what has to survive.
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelled = constraints.maxWidth >= 420;
            return Row(
              children: [
                for (final (i, step) in steps.indexed) ...[
                  // Fixed rather than Expanded: a stretching connector took a
                  // flex share from the pips and truncated the longest label.
                  if (i > 0)
                    Container(
                      width: 24,
                      height: 1,
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s8,
                      ),
                      color: tokens.borderSubtle,
                    ),
                  // A loose flex child: takes its natural width when there is
                  // room and ellipsizes when there is not. flex 0 would read
                  // as non-flex to RenderFlex and constrain nothing.
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
                    fontSize: 10,
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

/// The Space a form is about: its initials, its name and its host, with a tick
/// once its identity has been confirmed.
///
/// Shown only once `/version` has answered, because until then the only honest
/// thing to say about a typed address is nothing. The tick is about the pinned
/// fingerprint rather than about reachability - reaching a server says who
/// answered, not that it is the one you trusted last time.
class ServerIdentityChip extends StatelessWidget {
  const ServerIdentityChip({
    super.key,
    required this.spaceName,
    required this.host,
    this.confirmed = false,
  });

  final String spaceName;
  final String host;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final initials = spaceName.trim().isEmpty
        ? '?'
        : spaceName.trim().substring(0, spaceName.trim().length >= 2 ? 2 : 1);

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
              initials.toUpperCase(),
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
          if (confirmed)
            Icon(AppIcons.check, size: AppSizes.icon16, color: tokens.accent),
        ],
      ),
    );
  }
}
