// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The interactive surface for a module scene: it paints the current scene,
/// turns taps and control presses into actions, hands them back to the module,
/// and swaps in whatever scene comes back - so an animated or playable module
/// runs as a loop of ordinary stateless calls.
///
/// A module is a pure function of `(command, input)`; there is no session and
/// nothing persists between calls. This widget supplies the continuity: the
/// board rides in the scene's opaque [ModuleScene.state], and every step, tap
/// or reset is a fresh call carrying that state back. `play` is the only
/// client-side control - a timer that keeps asking the module to `step` until
/// the scene reports it can no longer change ([ModuleScene.live]) or the
/// viewer pauses.
///
/// It takes [runCommand] rather than reaching for the API itself, so it is
/// decoupled from how a scene gets run (a code block, the Dock panel) and can
/// be driven directly in a test.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import 'module_scene.dart';
import 'module_scene_painter.dart';

/// Runs one action against the module and returns its raw result. The action
/// and the current scene state are already packed into [input] as
/// `{"action":...,"state":...}`.
typedef ModuleSceneRunner =
    Future<api.RunModuleCommandResult> Function(String input);

class ModuleSceneView extends StatefulWidget {
  const ModuleSceneView({
    super.key,
    required this.initial,
    required this.runCommand,
  });

  final ModuleScene initial;
  final ModuleSceneRunner runCommand;

  @override
  State<ModuleSceneView> createState() => _ModuleSceneViewState();
}

class _ModuleSceneViewState extends State<ModuleSceneView> {
  static const _tick = Duration(milliseconds: 130);

  late ModuleScene _scene = widget.initial;
  Timer? _timer;
  bool _busy = false;
  bool _playing = false;
  String? _error;

  /// A genuinely new run (a re-Run of the block) carries a different seed
  /// state; an unrelated rebuild carries the same one and must not reset an
  /// animation already in progress, so the seed state is what decides.
  @override
  void didUpdateWidget(ModuleSceneView old) {
    super.didUpdateWidget(old);
    if (old.initial.state != widget.initial.state) {
      _stop();
      setState(() => _scene = widget.initial);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _send(String action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.runCommand(
        jsonEncode({'action': action, 'state': _scene.state ?? ''}),
      );
      if (!mounted) return;
      final next = result.ok && result.output != null
          ? parseModuleScene(result.output!)
          : null;
      setState(() {
        _busy = false;
        if (next != null) {
          _scene = next;
          if (!next.live) _stop();
        } else {
          _stop();
          _error = result.error ?? 'The module returned nothing to draw.';
        }
      });
    } on api.ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stop();
        _error = describeApiFailure('run this', e);
      });
    }
  }

  void _togglePlay() {
    if (_playing) {
      _stop();
      return;
    }
    setState(() => _playing = true);
    _timer = Timer.periodic(_tick, (_) {
      if (!_busy && _scene.live) {
        _send('step');
      } else if (!_scene.live) {
        _stop();
      }
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (_playing) _playing = false;
  }

  void _handleTapUp(TapUpDetails details, Size size) {
    final action = sceneTapAction(_scene, details.localPosition, size);
    if (action != null) _send(action);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final aspect = _scene.height == 0 ? 1.0 : _scene.width / _scene.height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: tokens.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: aspect <= 0 ? 1.0 : aspect,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.biggest;
                  return GestureDetector(
                    onTapUp: (d) => _handleTapUp(d, size),
                    child: CustomPaint(
                      painter: ModuleScenePainter(
                        scene: _scene,
                        tokens: tokens,
                      ),
                      size: size,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (_scene.status != null) ...[
          const SizedBox(height: AppSpacing.s8),
          Text(
            _scene.status!,
            style: AppText.caption.copyWith(
              fontFamily: AppFonts.mono,
              color: tokens.textSecondary,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.s8),
          AppErrorState(
            message: _error!,
            onDismiss: () => setState(() => _error = null),
          ),
        ],
        if (_scene.controls.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s8),
          Row(children: _controls(tokens)),
        ],
      ],
    );
  }

  List<Widget> _controls(AppTokens tokens) {
    final widgets = <Widget>[];
    for (final control in _scene.controls) {
      final button = _controlButton(control);
      if (button != null) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.s8),
            child: button,
          ),
        );
      }
    }
    return widgets;
  }

  Widget? _controlButton(String control) {
    switch (control) {
      case 'play':
        return AppIconButton(
          icon: _playing ? AppIcons.pause : AppIcons.play,
          semanticLabel: _playing ? 'Pause' : 'Play',
          active: _playing,
          onPressed: _togglePlay,
        );
      case 'step':
        return AppIconButton(
          icon: AppIcons.forward,
          semanticLabel: 'Step',
          onPressed: _busy ? null : () => _send('step'),
        );
      case 'random':
        return AppIconButton(
          icon: AppIcons.highlight,
          semanticLabel: 'Random',
          onPressed: _busy ? null : () => _send('random'),
        );
      case 'clear':
        return AppIconButton(
          icon: AppIcons.eraser,
          semanticLabel: 'Clear',
          onPressed: _busy ? null : () => _send('clear'),
        );
      case 'reset':
        return AppIconButton(
          icon: AppIcons.retry,
          semanticLabel: 'Reset',
          onPressed: _busy ? null : () => _send('reset'),
        );
      default:
        return null;
    }
  }
}
