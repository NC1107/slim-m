// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The hash/voice glyph a channel row or header leads with, swapped for a
/// lock when `@everyone` cannot view the channel - shared across the rail
/// rows and both channel headers so the tooltip and accessible label are
/// written once rather than four times.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class ChannelKindIcon extends StatelessWidget {
  const ChannelKindIcon({
    super.key,
    required this.isVoice,
    required this.restricted,
    required this.color,
    this.size = AppSizes.icon16,
  });

  final bool isVoice;

  /// See `Channel.restricted`'s own doc comment (slimm_api). False for an
  /// ordinary channel and for a server too old to say either way.
  final bool restricted;
  final Color color;
  final double size;

  static const _label = "Restricted channel: not visible to everyone";

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      restricted
          ? AppIcons.restrictedChannel
          : (isVoice ? AppIcons.voice : AppIcons.hash),
      size: size,
      color: color,
      semanticLabel: restricted ? _label : null,
    );
    return restricted ? Tooltip(message: _label, child: icon) : icon;
  }
}
