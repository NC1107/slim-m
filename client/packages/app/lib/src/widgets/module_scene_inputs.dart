// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The real text fields an [InputOp] asks for, laid over a painted scene.
///
/// A painter cannot draw a text field - it has a cursor, a keyboard, focus and
/// a selection - so `input` is the one scene op that is a widget rather than
/// paint. This overlays those widgets on the canvas at the scene coordinates
/// the module gave, and reports a submission back as an action.
///
/// Its own file because it is the only stateful part of rendering a scene:
/// everything else in `module_scene_view.dart` is derived from the current
/// scene, and a field in the middle of being typed into is not.
///
/// The module owns the value. Whatever comes back in the next scene is what the
/// field shows, so a module can correct, clear or reformat a submission. The one
/// exception is a field somebody is typing in right now: overwriting that under
/// their cursor would make the app feel like it was fighting them, so a scene
/// arriving while a field has focus leaves that field alone.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slimm_design_system/design_system.dart';

import 'module_scene.dart';

class SceneInputOverlay extends StatefulWidget {
  const SceneInputOverlay({
    super.key,
    required this.scene,
    required this.size,
    required this.onSubmit,
  });

  final ModuleScene scene;

  /// The painted box, so scene units can be scaled the way the painter scales
  /// them.
  final Size size;

  /// Called with `"<submit>:<text>"`, the same colon-separated action shape a
  /// tapped cell reports.
  final ValueChanged<String> onSubmit;

  @override
  State<SceneInputOverlay> createState() => _SceneInputOverlayState();
}

class _SceneInputOverlayState extends State<SceneInputOverlay> {
  /// One controller and focus node per submit name, kept across scenes so
  /// typing survives a frame arriving from somebody else's action.
  final _controllers = <String, TextEditingController>{};
  final _focus = <String, FocusNode>{};

  /// What the module last said the value was, so a scene that did not change it
  /// does not get to reset the field.
  final _lastFromModule = <String, String>{};

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SceneInputOverlay old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Brings the controllers in line with the current scene: a field per input
  /// op, seeded from the module's value, and nothing left over for an op that
  /// has gone.
  void _sync() {
    final ops = _inputs();
    final names = ops.map((op) => op.submit).toSet();

    for (final name in _controllers.keys.toList()) {
      if (names.contains(name)) continue;
      _controllers.remove(name)?.dispose();
      _focus.remove(name)?.dispose();
      _lastFromModule.remove(name);
    }

    for (final op in ops) {
      final controller = _controllers.putIfAbsent(
        op.submit,
        () => TextEditingController(text: op.value),
      );
      _focus.putIfAbsent(op.submit, FocusNode.new);

      final changedByModule = _lastFromModule[op.submit] != op.value;
      _lastFromModule[op.submit] = op.value;
      final beingTyped = _focus[op.submit]?.hasFocus ?? false;
      if (changedByModule && !beingTyped && controller.text != op.value) {
        controller.text = op.value;
      }
    }
  }

  List<InputOp> _inputs() => widget.scene.ops.whereType<InputOp>().toList();

  @override
  Widget build(BuildContext context) {
    final ops = _inputs();
    if (ops.isEmpty) return const SizedBox.shrink();

    final sx = widget.scene.width == 0
        ? 1.0
        : widget.size.width / widget.scene.width;
    final sy = widget.scene.height == 0
        ? 1.0
        : widget.size.height / widget.scene.height;

    return Stack(
      children: [
        for (final op in ops)
          Positioned(
            left: op.x * sx,
            top: op.y * sy,
            width: op.w * sx,
            child: AppInput(
              controller: _controllers[op.submit],
              focusNode: _focus[op.submit],
              placeholder: op.placeholder,
              size: AppInputSize.sm,
              inputFormatters: [LengthLimitingTextInputFormatter(op.maxLength)],
              semanticLabel: op.placeholder ?? 'Scene input',
              textInputAction: TextInputAction.done,
              onSubmitted: (text) =>
                  widget.onSubmit('${op.submit}:${text.trim()}'),
            ),
          ),
      ],
    );
  }
}
