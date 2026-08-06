// SPDX-License-Identifier: Apache-2.0
/// A [CanvasBar] wrapped for a widget test, and its own fill-in-the-blanks
/// constructor - shared between `canvas_bar_test.dart` (everything the bar
/// does) and `canvas_bar_shape_kind_test.dart` (the shape-kind picker and
/// the armed icon it drives), which is what `canvas_bar_test.dart` split
/// into once it crossed the 500-line hard limit.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slimm_app/src/screens/canvas/canvas_bar.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

Widget wrapCanvasBar(Widget child, {double width = 800}) => MaterialApp(
  theme: buildTheme(Brightness.dark, AppTokens.dark),
  home: Scaffold(
    body: SizedBox(width: width, child: child),
  ),
);

CanvasBar buildCanvasBar({
  CanvasTool tool = CanvasTool.pen,
  ValueChanged<CanvasTool>? onToolChanged,
  bool canUndo = false,
  VoidCallback? onUndo,
  bool canManage = false,
  ValueListenable<int>? objectCount,
  Future<void> Function()? onClear,
  VoidCallback? onPasteImage,
  VoidCallback? onRecenter,
  ValueListenable<String?>? selection,
  ValueChanged<String>? onBringToFront,
  ValueChanged<String>? onSendToBack,
  ValueChanged<String>? onDeleteSelected,
  bool activityLogOpen = false,
  VoidCallback? onToggleActivityLog,
  CanvasShapeKind shapeKind = CanvasShapeKind.rectangle,
  ValueChanged<CanvasShapeKind>? onShapeKindChanged,
  bool hasSelfBubble = false,
  bool selfBubbleHidden = false,
  VoidCallback? onToggleSelfBubbleHidden,
}) => CanvasBar(
  channelId: 'c1',
  onClose: () {},
  tool: tool,
  onToolChanged: onToolChanged ?? (_) {},
  canUndo: canUndo,
  onUndo: onUndo ?? () {},
  canManage: canManage,
  objectCount: objectCount ?? ValueNotifier<int>(3),
  onClear: onClear ?? () async {},
  onPasteImage: onPasteImage ?? () {},
  onRecenter: onRecenter ?? () {},
  selection: selection ?? ValueNotifier<String?>(null),
  onBringToFront: onBringToFront ?? (_) {},
  onSendToBack: onSendToBack ?? (_) {},
  onDeleteSelected: onDeleteSelected ?? (_) {},
  activityLogOpen: activityLogOpen,
  onToggleActivityLog: onToggleActivityLog ?? () {},
  shapeKind: shapeKind,
  onShapeKindChanged: onShapeKindChanged ?? (_) {},
  hasSelfBubble: hasSelfBubble,
  selfBubbleHidden: selfBubbleHidden,
  onToggleSelfBubbleHidden: onToggleSelfBubbleHidden ?? () {},
);
