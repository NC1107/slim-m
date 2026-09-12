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
  /// How often play asks for the next generation, at its fastest.
  ///
  /// Not the rate it settles at. The shared code-block route is rate limited
  /// as an ordinary write (30 burst, 5 a second refilling), and playing at
  /// this tick outruns that: a long run used to sail through the burst and
  /// then fail outright with "too many requests", which is a rate limit doing
  /// its job and an animation handling it badly. [_backoff] is what turns that
  /// into pacing rather than a stop.
  static const _tick = Duration(milliseconds: 130);

  /// The ceiling [_interval] backs off to. Beyond a couple of seconds a board
  /// is not really playing any more, and something is wrong that waiting
  /// longer will not fix.
  static const _maxTick = Duration(seconds: 2);

  /// The interval play is currently running at, between [_tick] and
  /// [_maxTick]. Doubles on a refused call and eases back on a run of good
  /// ones, so a deployment's own limit is found rather than assumed.
  Duration _interval = _tick;

  late ModuleScene _scene = widget.initial;
  Timer? _timer;
  bool _busy = false;
  bool _playing = false;
  String? _error;

  /// Actions waiting on the one in flight, oldest first.
  ///
  /// A module call is a round trip and only one runs at a time, so a drag
  /// across a grid produces actions faster than they can be sent. Dropping the
  /// ones that arrive while busy - which is what the [_busy] guard in [_send]
  /// does on its own - would leave holes in a drawn line, so they queue here
  /// and drain in order instead.
  final _queue = <String>[];

  /// Capped so a long drag on a fine grid cannot build a backlog the board
  /// spends a minute catching up on. A dropped tail is better than a board
  /// that keeps moving after the finger stops.
  static const _maxQueue = 64;

  /// Cells already sent during the current drag, so crossing one twice does
  /// not toggle it back off. Cleared when the drag starts.
  final _paintedThisDrag = <String>{};

  /// The last few scene states this view produced itself.
  ///
  /// A scene that belongs to a message is shared: every action stores the new
  /// output on the message and broadcasts it, so this widget's own step comes
  /// straight back as a new [widget.initial]. Without this it read as somebody
  /// starting a new run and stopped the very timer that had just produced it -
  /// press play, watch exactly one generation, then nothing.
  final _ownStates = <String>{};
  static const _ownStateMemory = 8;

  @override
  void initState() {
    super.initState();
    _rememberOwn(widget.initial.state);
  }

  /// A genuinely new run - somebody re-Ran the block, or another viewer acted
  /// on a shared scene - resets this view and stops any animation. This
  /// widget's own work does not, even though on the shared path it arrives by
  /// exactly the same route: see [_ownStates].
  @override
  void didUpdateWidget(ModuleSceneView old) {
    super.didUpdateWidget(old);
    if (old.initial.state == widget.initial.state) return;
    if (_isOwnWork(widget.initial.state)) {
      _rememberOwn(widget.initial.state);
      if (_scene.state != widget.initial.state) {
        setState(() => _scene = widget.initial);
      }
      return;
    }
    _stop();
    _queue.clear();
    _paintedThisDrag.clear();
    _rememberOwn(widget.initial.state);
    setState(() => _scene = widget.initial);
  }

  /// Whether a scene arriving from above is this view's own, rather than a new
  /// run to reset for.
  ///
  /// A call in flight or a queue still draining is the answer on its own: the
  /// broadcast can beat this view's own response back, so the state would not
  /// be in [_ownStates] yet even though it is ours.
  bool _isOwnWork(String? state) =>
      _busy ||
      _queue.isNotEmpty ||
      (state != null && _ownStates.contains(state));

  void _rememberOwn(String? state) {
    if (state == null) return;
    _ownStates.add(state);
    if (_ownStates.length > _ownStateMemory) {
      _ownStates.remove(_ownStates.first);
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
      if (next != null) _rememberOwn(next.state);
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
    } on api.RateLimitedException catch (e) {
      if (!mounted) return;
      // Only play can outrun the budget; see _backOff.
      if (_playing) {
        setState(() => _busy = false);
        _backOff(e.retryAfter);
        return;
      }
      setState(() {
        _busy = false;
        _stop();
        _error = describeApiFailure('run this', e);
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
      _stopAndRepaint();
      return;
    }
    // A fresh press starts at full speed again; see _backOff.
    _interval = _tick;
    setState(() => _playing = true);
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) {
      if (!_busy && _scene.live) {
        _send('step');
      } else if (!_scene.live) {
        _stopAndRepaint();
      }
    });
  }

  /// Slows play after the server refused a call for asking too fast.
  ///
  /// Doubles, or waits whatever `Retry-After` asked for if that is longer,
  /// capped at [_maxTick]. It does not speed back up inside a run: creeping
  /// back toward [_tick] would find the limit again, and a board that keeps
  /// stuttering into refusals is worse than one that settled slightly slow.
  /// Pressing play again is how you ask for full speed.
  void _backOff(Duration? retryAfter) {
    final doubled = _interval * 2;
    var next = retryAfter != null && retryAfter > doubled
        ? retryAfter
        : doubled;
    if (next > _maxTick) next = _maxTick;
    _interval = next;
    if (_playing) _startTimer();
  }

  /// Cancels the timer and clears the flag, with no rebuild of its own: two of
  /// the three callers are already inside a `setState`, and nesting one is an
  /// error. [_stopAndRepaint] is the version for the callers that are not.
  void _stop() {
    _timer?.cancel();
    _timer = null;
    _playing = false;
  }

  /// Stops, and repaints the control that says so.
  ///
  /// Pressing pause used to call [_stop] directly, which left `_playing` false
  /// while the button still drew a pause glyph and its active highlight. The
  /// animation really had stopped, so the only feedback was the board going
  /// still, and pressing the button again started it while the icon still said
  /// pause - a control whose state was the opposite of what it showed.
  void _stopAndRepaint() {
    if (!mounted) {
      _stop();
      return;
    }
    setState(_stop);
  }

  /// Where the current gesture began, remembered because `onPanStart` reports
  /// the point at which the drag was *recognised* rather than the point the
  /// finger came down on. Those are a cell or two apart, so a line drawn by
  /// dragging was missing the cell it started in until this was recorded here.
  Offset? _downAt;

  /// The raw pointer-down, not `onTapDown`: the tap recogniser is rejected
  /// before its own deadline when a drag is quick, so `onTapDown` never fires
  /// for exactly the gestures this needs to know the origin of.
  void _handlePointerDown(PointerDownEvent event) {
    _downAt = event.localPosition;
    _paintedThisDrag.clear();
  }

  void _handleTapUp(TapUpDetails details, Size size) {
    final action = sceneTapAction(_scene, details.localPosition, size);
    if (action != null) _enqueue(action);
  }

  /// Paints the cell the finger actually landed on, then the one the drag was
  /// recognised in. The dedupe set makes the common case, where they are the
  /// same cell, a single paint.
  void _handlePanStart(DragStartDetails details, Size size) {
    final down = _downAt;
    if (down != null) _paintCell(down, size);
    _paintCell(details.localPosition, size);
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) =>
      _paintCell(details.localPosition, size);

  /// Sends the cell under [local] once per drag. Ops that answer a bare action
  /// rather than a cell (a button drawn into the scene) are ignored here: a
  /// drag across one is not a press of it.
  void _paintCell(Offset local, Size size) {
    final action = sceneTapAction(_scene, local, size);
    if (action == null || !action.contains(':')) return;
    if (!_paintedThisDrag.add(action)) return;
    _enqueue(action);
  }

  void _enqueue(String action) {
    if (_queue.length >= _maxQueue) return;
    _queue.add(action);
    unawaited(_drain());
  }

  /// Sends queued actions, coalescing what the module said it can read in one
  /// go. Re-entrant calls return immediately, so the drain already running is
  /// the only one.
  Future<void> _drain() async {
    if (_busy || _queue.isEmpty) return;
    while (_queue.isNotEmpty && mounted) {
      await _send(_takeNext());
    }
  }

  /// The next call to make: one queued action, or every leading action sharing
  /// a prefix the module reads as a list, joined into one.
  ///
  /// A whole drag becomes a single round trip that way. Without it the queue
  /// still drains in order and nothing is lost - it just costs a call per cell,
  /// which over a real network is what made drawing feel like work.
  String _takeNext() {
    final first = _queue.removeAt(0);
    final prefix = first.split(':').first;
    if (!first.contains(':') || !sceneAllowsTapBatch(_scene, first)) {
      return first;
    }
    final cells = <String>[first.substring(prefix.length + 1)];
    while (_queue.isNotEmpty && _queue.first.startsWith('$prefix:')) {
      cells.add(_queue.removeAt(0).substring(prefix.length + 1));
    }
    return '$prefix:${cells.join(';')}';
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
                  return Listener(
                    onPointerDown: _handlePointerDown,
                    child: GestureDetector(
                      onTapUp: (d) => _handleTapUp(d, size),
                      onPanStart: (d) => _handlePanStart(d, size),
                      onPanUpdate: (d) => _handlePanUpdate(d, size),
                      child: CustomPaint(
                        painter: ModuleScenePainter(
                          scene: _scene,
                          tokens: tokens,
                        ),
                        size: size,
                      ),
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

  /// One control, or null for a name this client does not offer.
  ///
  /// Deliberately never disabled on [_busy]. It used to be, and while playing
  /// that meant every control greyed out and came back on each generation -
  /// a visible flicker at eight times a second, reported as the buttons
  /// flashing. A press landing mid-call is already a no-op, because [_send]
  /// refuses a second call while one is in flight, so disabling them bought
  /// nothing the guard did not already do and cost that.
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
          onPressed: () => _send('step'),
        );
      case 'random':
        return AppIconButton(
          icon: AppIcons.highlight,
          semanticLabel: 'Random',
          onPressed: () => _send('random'),
        );
      case 'clear':
        return AppIconButton(
          icon: AppIcons.eraser,
          semanticLabel: 'Clear',
          onPressed: () => _send('clear'),
        );
      case 'reset':
        return AppIconButton(
          icon: AppIcons.retry,
          semanticLabel: 'Reset',
          onPressed: () => _send('reset'),
        );
      default:
        return null;
    }
  }
}
