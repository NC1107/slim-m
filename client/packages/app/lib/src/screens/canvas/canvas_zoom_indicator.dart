// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one on-screen readout of how zoomed in the canvas currently is.
///
/// The canvas is a bounded large world, not literally infinite (see
/// `CLAUDE.md`), and panning or pinching around it left nothing on screen
/// saying how far zoomed in or out a person had gone - the owner's backlog
/// named this directly as a gap. This closes it with the smallest thing that
/// answers the question, a small pill in the one corner nothing else already
/// claims: `canvas_presence_roster.dart`'s own doc maps the error/truncation
/// banners to top-left-to-center and the floating dock to bottom-center,
/// which leaves bottom-left free.
///
/// Deliberately not a minimap, and not a position readout either: a
/// position needs [CanvasDocument.contentBounds], which that getter's own
/// doc says is a plain scan meant for one Recenter tap, never once a frame -
/// exactly the cost a camera-driven rebuild here would pay on every pan and
/// pinch. Zoom alone costs nothing extra: [CanvasDocument.camera] is already
/// read every frame elsewhere, and answers most of what "where am I" means
/// for a roughly dozen-person canvas, where the existing Recenter action is
/// already the way back if a person really is lost.
library;

import 'package:flutter/widgets.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

class CanvasZoomIndicator extends StatelessWidget {
  const CanvasZoomIndicator({
    super.key,
    required this.document,
    required this.tokens,
  });

  final CanvasDocument document;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: SafeArea(
      minimum: const EdgeInsets.all(AppSpacing.s12),
      child: IgnorePointer(
        child: ListenableBuilder(
          listenable: document,
          builder: (context, _) {
            final percent = (document.camera.zoom * 100).round();
            return Semantics(
              container: true,
              label: 'Zoom $percent percent',
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s8,
                  vertical: AppSpacing.s4,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadii.full),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: ExcludeSemantics(
                  child: Text(
                    '$percent%',
                    style: AppText.caption.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: AppWeights.medium,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
