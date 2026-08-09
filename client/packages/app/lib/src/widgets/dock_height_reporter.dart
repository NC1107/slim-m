// SPDX-License-Identifier: Apache-2.0
/// Measures [child]'s real rendered height after every frame and publishes
/// it to `bottomDockReservationProvider`, so `app_snackbar.dart` knows how
/// much of the bottom edge a floating dock actually occupies right now.
///
/// Measured rather than guessed at a fixed constant: the dock this wraps
/// stacks one row or two depending on width and on whether a call is
/// present (`CanvasCallDock`'s own doc comment), so a hardcoded height would
/// either under-reserve on the tallest shape or waste space on the shortest
/// one. Publishes 0 on dispose, since a dock that has unmounted reserves
/// nothing.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/dock_reservation.dart';

class DockHeightReporter extends ConsumerStatefulWidget {
  const DockHeightReporter({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DockHeightReporter> createState() => _DockHeightReporterState();
}

class _DockHeightReporterState extends ConsumerState<DockHeightReporter> {
  final _key = GlobalKey();

  /// Captured once: a disposed [ConsumerState] cannot read `ref` again, and
  /// the reservation this dock owns must still be zeroed out on the way down.
  late final StateController<double> _reservation = ref.read(
    bottomDockReservationProvider.notifier,
  );
  double _lastReported = 0;

  void _report() {
    final height = _key.currentContext?.size?.height ?? 0;
    if (height == _lastReported) return;
    _lastReported = height;
    _reservation.state = height;
  }

  @override
  void dispose() {
    _reservation.state = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _report());
    return KeyedSubtree(key: _key, child: widget.child);
  }
}
