// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

void main() => runApp(const SlimMApp());

/// Phase 0 shell: proves the design tokens flow through the theme. The adaptive
/// layout, routing, and messaging surfaces arrive in Phase 2.
class SlimMApp extends StatelessWidget {
  const SlimMApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'slim-m',
      theme: _theme(Brightness.light, AppTokens.light),
      darkTheme: _theme(Brightness.dark, AppTokens.dark),
      home: const _Placeholder(),
    );
  }

  ThemeData _theme(Brightness brightness, AppTokens tokens) {
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: tokens.surfaceBase,
      extensions: [tokens],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Scaffold(
      body: Center(
        child: Text(
          'slim-m',
          style: TextStyle(color: tokens.accent, fontSize: 24),
        ),
      ),
    );
  }
}
