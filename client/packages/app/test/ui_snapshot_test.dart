// SPDX-License-Identifier: Apache-2.0
/// The real shell, rendered at every resolution the product ships to.
///
/// This is the matrix `design_system`'s golden matrix is not: that one renders
/// a synthetic sample of chrome, so a regression in an actual widget (the
/// rail's manage button drifting out of its row, a reaction chip stretching
/// the width of the pane) is invisible to it.
///
/// Two things run here. The overflow assertions run everywhere including CI.
/// The PNGs are written only under SLIMM_UI_SNAPSHOTS=1, because they exist to
/// be looked at rather than diffed: Skia and font rasterisation differ between
/// this box and a CI runner, so a committed reference would be permanently red.
///
/// Write them with `scripts/ui-snapshots.sh`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/admin_providers.dart'
    show spaceAnalyticsProvider;
import 'package:slimm_app/src/providers/sync_controller.dart'
    show SyncStatus, initialSyncCompleteProvider, syncControllerProvider;
import 'package:slimm_app/src/providers/threads.dart' show openThreadProvider;
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/canvas/canvas_pane.dart'
    show canvasOpenProvider;
import 'package:slimm_app/src/widgets/channel_rail.dart'
    show channelRailVisibleProvider;

import 'ui_snapshot_support.dart';
import 'voice_snapshot_fixtures.dart'
    show
        SnapshotVoiceController,
        connectedCallState,
        connectingState,
        dmChannelId;
import 'voice_snapshot_scenarios.dart';

/// The surfaces worth a picture: the route, and which viewports to render.
///
/// `channel` straddles every breakpoint it owns because width changes its
/// structure. A voice channel needs the identical breakpoint treatment - it
/// is the same shell, just a different `kind` - but it also needs its
/// controller pinned, or the body shows a real, unmocked auto-join that
/// settles into a blank frame long before this matrix pumps far enough to
/// see it fail; see `_shellStateSurfaces`'s own `voice` entry for that.
/// Each standalone screen adds the pair that brackets its *own* breakpoint
/// to a phone and a desktop render, rather than every screen sampling every
/// boundary: a screen with no 800px floor of its own gains nothing from
/// being rendered at 799 and 800.
const _surfaces = <String, ({String route, List<String> viewports})>{
  'channel': (
    route: '/channels/c-general',
    viewports: [
      'phone-portrait',
      'phone-landscape',
      'tablet-portrait',
      'desktop-narrow',
      'desktop',
      ...compactBracket,
      'expanded-999',
      'expanded-1000',
    ],
  ),
  // The default landing state right after sign-in, absent from this matrix until now.
  'no-channel-selected': (
    route: '/channels',
    viewports: [
      ...phoneAndDesktop,
      ...compactBracket,
      'expanded-999',
      'expanded-1000',
    ],
  ),
  // c-empty has no messages, which #general never does, so only it can show the transcript's offline-empty copy.
  'channel-offline-empty': (
    route: '/channels/c-empty',
    viewports: phoneAndDesktop,
  ),
  // An ordinary DM, distinct from the self-DM personal space: renders the rail's DM section and a real transcript.
  'dm-normal-transcript': (
    route: '/channels/c-dm-ada',
    viewports: phoneAndDesktop,
  ),
  'onboarding': (
    route: '/join',
    viewports: [
      ...phoneAndDesktop,
      'stepper-467',
      'stepper-468',
      'onboarding-899',
      'onboarding-900',
    ],
  ),
  'sign-in': (
    route: '/sign-in',
    viewports: [...phoneAndDesktop, 'onboarding-899', 'onboarding-900'],
  ),
  'settings': (
    route: '/settings',
    viewports: [
      ...phoneAndDesktop,
      ...compactBracket,
      'settings-799',
      'settings-800',
    ],
  ),
  'space-settings': (
    route: '/settings/space',
    viewports: [
      ...phoneAndDesktop,
      ...compactBracket,
      'settings-799',
      'settings-800',
    ],
  ),
  'admin-roles': (
    route: '/settings/roles',
    viewports: [...phoneAndDesktop, ...compactBracket],
  ),
  'admin-invites': (
    route: '/settings/invites',
    viewports: [...phoneAndDesktop, ...compactBracket],
  ),
  'admin-reports': (
    route: '/settings/reports',
    viewports: [...phoneAndDesktop, ...compactBracket],
  ),
  'admin-overwrites': (
    route: '/settings/permissions',
    viewports: [...phoneAndDesktop, ...compactBracket],
  ),
  'admin-emoji': (
    route: '/settings/emoji',
    viewports: [...phoneAndDesktop, ...compactBracket],
  ),
  'admin-categories': (
    route: '/settings/categories',
    viewports: [...phoneAndDesktop, ...compactBracket],
  ),
  'admin-removed-members': (
    route: '/settings/removed-members',
    viewports: [...phoneAndDesktop, ...compactBracket],
  ),
  'admin-analytics': (
    route: '/settings/analytics',
    viewports: [...phoneAndDesktop, ...compactBracket],
  ),
  'debug-log': (
    route: '/settings/debug-log',
    viewports: [...phoneAndDesktop, ...compactBracket],
  ),
  // The stacked-header bug only ever showed past kCompactWidth; the compact bracket proves it stays clean there too.
  'thread': (
    route: '/thread/c-thread',
    viewports: [
      ...phoneAndDesktop,
      ...compactBracket,
      'expanded-999',
      'expanded-1000',
    ],
  ),
  // No call open: dm-call-button-idle; -active-lit needs dmCallActivityProvider reporting a ring, which nothing here drives.
  'dm': (route: '/channels/$dmChannelId', viewports: phoneAndDesktop),
};

/// `ReportCard`'s own nested resolve needs `renderSurface`'s
/// `settleNestedResolve` pump, or `expectSettled` catches it as a
/// mid-flight capture - see PR #545 ("report card overflow").
const _nestedResolveSurfaces = {
  'admin-reports',
  // Wide space settings embeds the reports pane and its nested resolve.
  'space-settings',
};

/// A real, benign difference between two valid loading states rather than
/// a placeholder standing in for content - see `expectSettled`'s own doc
/// comment for why `thread` is the one surface this is true of today.
const _knownTransientSurfaces = {'thread'};

/// Enabled analytics with a full month of days and a real 24-hour histogram,
/// so every chart on that screen actually draws rather than collapsing to an
/// empty state. The numbers are deliberately wide (a five-figure total, an
/// uneven histogram) because a narrow chart with tidy values would not
/// exercise the label widths this is here to catch.
final _analyticsFixture = api.SpaceAnalytics(
  enabled: true,
  stats: api.AnalyticsStats(
    totalMessages: 48213,
    memberCount: 12,
    channelCount: 7,
    attachmentBytes: 734003200,
    messagesByDay: [
      for (var day = 1; day <= 30; day++)
        api.AnalyticsDayCount(
          date: '2026-07-${day.toString().padLeft(2, '0')}',
          count: 40 + (day * 37) % 900,
        ),
    ],
    activeHours: [for (var hour = 0; hour < 24; hour++) 20 + (hour * 53) % 400],
    memorySamples: [
      for (var sample = 0; sample < 24; sample++)
        api.AnalyticsMemorySample(
          sampledAt: 1785000000000 + sample * 3600000,
          rssBytes: 9000000 + (sample * 811) % 4000000,
        ),
    ],
  ),
);

/// Shell states reachable only by overriding a provider the plain [_surfaces]
/// table has no way to reach: a collapsed rail, a day divider forced to show,
/// the transcript's connecting/genuinely-empty states (which the default
/// fixture's offline `SyncController` can never produce on its own), and a
/// voice channel pinned to its connecting state rather than left to a real,
/// unmocked auto-join.
final _shellStateSurfaces =
    <
      String,
      ({
        String route,
        List<String> viewports,
        List<Override> Function() overrides,
      })
    >{
      // The plain admin-analytics surface renders the toggle off, which is
      // the default and covers the empty screen; every chart sits behind it,
      // and a bar chart at phone width is the part of that screen most likely
      // to overflow, so the enabled state needs a surface of its own.
      'admin-analytics-enabled': (
        route: '/settings/analytics',
        viewports: const [...phoneAndDesktop, ...compactBracket],
        overrides: () => [
          spaceAnalyticsProvider.overrideWith((ref) => _analyticsFixture),
        ],
      ),
      'rail-collapsed': (
        route: '/channels/c-general',
        viewports: const ['desktop-narrow', 'desktop'],
        overrides: () => [
          channelRailVisibleProvider.overrideWith((ref) => false),
        ],
      ),
      // The thread docked beside the transcript, the presentation an in-app open now takes at expanded widths (UX1); the `thread` surface's pushed route still covers the compact modal.
      'thread-docked': (
        route: '/channels/c-general',
        viewports: const ['expanded-999', 'expanded-1000'],
        overrides: () => [openThreadProvider.overrideWith((ref) => 'c-thread')],
      ),
      'channel-day-divider': (
        route: '/channels/c-general',
        viewports: phoneAndDesktop,
        overrides: () => [
          initialSyncCompleteProvider.overrideWith((ref) => true),
        ],
      ),
      'channel-catching-up': (
        route: '/channels/c-empty',
        viewports: phoneAndDesktop,
        overrides: () => [
          syncControllerProvider.overrideWith(
            (ref) => FixedSyncController(ref, SyncStatus.connecting),
          ),
        ],
      ),
      'channel-genuinely-empty': (
        route: '/channels/c-empty',
        viewports: phoneAndDesktop,
        overrides: () => [
          syncControllerProvider.overrideWith(
            (ref) => FixedSyncController(ref, SyncStatus.live),
          ),
          initialSyncCompleteProvider.overrideWith((ref) => true),
        ],
      ),
      // Pinned to the connecting state: what every voice channel arrival truthfully shows first, at every breakpoint the shell itself owns.
      'voice': (
        route: '/channels/c-main',
        viewports: [
          'phone-portrait',
          'phone-landscape',
          'tablet-portrait',
          'desktop-narrow',
          'desktop',
          ...compactBracket,
          'expanded-999',
          'expanded-1000',
        ],
        overrides: () => [
          voiceControllerProvider.overrideWith(
            (ref) => SnapshotVoiceController(ref, connectingState),
          ),
        ],
      ),
    };

/// The canvas replaces the whole conversation body, header included, at
/// every width. That is only reachable by forcing `canvasOpenProvider`
/// open, which the shared render below has no way to do for a plain
/// [_surfaces] entry, so these get their own small table and loop.
///
/// The compact bracket is what a stacked-header regression needs: the outer
/// app bar there is a second widget entirely (`HomeShell`'s own `Scaffold`,
/// not `ConversationPane`), so no other breakpoint proves it stays
/// suppressed.
///
/// `withVoice` is what makes `canvas-voice` actually live up to its name:
/// until this was added it forced the canvas open on `c-main` but applied
/// no `voiceControllerProvider` override, so `callDockDataFor` read the
/// call as not-connected and the combined call-and-canvas dock, plus every
/// camera-bubble state `_callParticipants()` gates on a live call in this
/// exact channel, never rendered here despite the name. See
/// `docs/reports/screen-inventory-canvas.md`'s "single highest-value gap".
const _canvasSurfaces =
    <
      String,
      ({String route, String channelId, List<String> viewports, bool withVoice})
    >{
      'canvas': (
        route: '/channels/c-general',
        channelId: 'c-general',
        viewports: [...phoneAndDesktop, ...compactBracket],
        withVoice: false,
      ),
      'canvas-voice': (
        route: '/channels/c-main',
        channelId: 'c-main',
        viewports: [
          'phone-portrait',
          ...compactBracket,
          'expanded-999',
          'expanded-1000',
        ],
        withVoice: true,
      ),
    };

/// The connected in-call surface, forced through `voiceControllerProvider`
/// the same way the canvas surfaces above force `canvasOpenProvider` - the
/// `voice` entry in [_shellStateSurfaces] only ever reaches the connecting
/// state, since nothing there drives a real join. One person sharing their screen
/// with their camera on, plus a second camera-only participant, is the
/// shape the owner reported as three boxes that did not fit a phone;
/// `phone-portrait` is tall and narrow on purpose, the case that report
/// named, with `phone-landscape` (short and wide) as its counterpart.
const _voiceCallSurfaces = <String, ({String route, List<String> viewports})>{
  'voice-in-call': (
    route: '/channels/c-main',
    viewports: [
      'phone-portrait',
      'phone-landscape',
      'desktop',
      ...compactBracket,
    ],
  ),
};

void main() {
  setUpAll(loadRealFonts);

  for (final theme in const ['dark', 'light']) {
    for (final surface in _surfaces.entries) {
      for (final viewportName in surface.value.viewports) {
        testWidgets(
          '${surface.key} at $viewportName ($theme) fits its viewport',
          (tester) async {
            await renderSurface(
              tester,
              surface.value.route,
              viewportName,
              theme,
              '${surface.key}-$viewportName-$theme',
              settleNestedResolve: _nestedResolveSurfaces.contains(surface.key),
              knownTransient: _knownTransientSurfaces.contains(surface.key),
            );
          },
        );
      }
    }

    for (final surface in _shellStateSurfaces.entries) {
      for (final viewportName in surface.value.viewports) {
        testWidgets(
          '${surface.key} at $viewportName ($theme) fits its viewport',
          (tester) async {
            await renderSurface(
              tester,
              surface.value.route,
              viewportName,
              theme,
              '${surface.key}-$viewportName-$theme',
              overrides: surface.value.overrides(),
            );
          },
        );
      }
    }

    for (final surface in _canvasSurfaces.entries) {
      for (final viewportName in surface.value.viewports) {
        testWidgets(
          '${surface.key} at $viewportName ($theme) fits its viewport',
          (tester) async {
            await renderSurface(
              tester,
              surface.value.route,
              viewportName,
              theme,
              '${surface.key}-$viewportName-$theme',
              overrides: [
                canvasOpenProvider.overrideWith(
                  (ref) => surface.value.channelId,
                ),
                if (surface.value.withVoice)
                  voiceControllerProvider.overrideWith(
                    (ref) => SnapshotVoiceController(ref, connectedCallState),
                  ),
              ],
            );
          },
        );
      }
    }

    for (final surface in _voiceCallSurfaces.entries) {
      for (final viewportName in surface.value.viewports) {
        testWidgets(
          '${surface.key} at $viewportName ($theme) fits its viewport',
          (tester) async {
            await renderSurface(
              tester,
              surface.value.route,
              viewportName,
              theme,
              '${surface.key}-$viewportName-$theme',
              overrides: [
                voiceControllerProvider.overrideWith(
                  (ref) => SnapshotVoiceController(ref, connectedCallState),
                ),
              ],
            );
          },
        );
      }
    }

    // Every other voice and DM-call state: registered from voice_snapshot_scenarios.dart, for this file's own line budget.
    registerVoiceCallVariants(theme, renderSurface);
    registerVoiceJoinPreview(theme, renderSurface);
    registerVoiceRejoin(theme, renderSurface);
    registerWhoIsHere(theme, renderSurface);
    registerWhoIsHereUnknown(theme, renderSurface);
    registerDmCall(theme, renderSurface);
  }
}
