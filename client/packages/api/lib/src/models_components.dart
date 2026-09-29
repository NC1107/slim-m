// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Buttons a bot attaches to its own message. See
/// docs/decisions/0039-bot-message-buttons.md.
library;

enum ComponentButtonStyle {
  primary,
  secondary,
  danger,
  link;

  /// An unrecognised style from a newer server reads as [secondary], so the
  /// button still renders and can still be pressed.
  static ComponentButtonStyle fromWire(String? value) => switch (value) {
        'primary' => primary,
        'danger' => danger,
        'link' => link,
        _ => secondary,
      };
}

class MessageButton {
  const MessageButton({
    required this.label,
    required this.style,
    this.customId,
    this.url,
    this.disabled = false,
  });

  final String label;
  final ComponentButtonStyle style;

  /// Null on a link button, which never reaches the bot.
  final String? customId;

  /// Set only on a link button.
  final String? url;
  final bool disabled;

  factory MessageButton.fromJson(Map<String, dynamic> json) => MessageButton(
        label: json['label'] as String,
        style: ComponentButtonStyle.fromWire(json['style'] as String?),
        customId: json['custom_id'] as String?,
        url: json['url'] as String?,
        disabled: json['disabled'] as bool? ?? false,
      );
}

class ComponentRow {
  const ComponentRow({required this.buttons});

  final List<MessageButton> buttons;

  factory ComponentRow.fromJson(Map<String, dynamic> json) => ComponentRow(
        buttons: (json['buttons'] as List<dynamic>)
            .map((b) => MessageButton.fromJson(b as Map<String, dynamic>))
            .toList(growable: false),
      );

  static List<ComponentRow> listFromJson(Object? json) =>
      (json as List<dynamic>?)
          ?.map((r) => ComponentRow.fromJson(r as Map<String, dynamic>))
          .toList(growable: false) ??
      const [];
}
