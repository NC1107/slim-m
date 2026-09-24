// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Bot command registration wire shapes. See
/// docs/decisions/0031-bot-command-registration.md.
library;

/// One bot command offered in a channel, from `GET
/// /channels/{channelId}/bot-commands`; already permission- and
/// visibility-filtered server-side.
class ChannelBotCommand {
  const ChannelBotCommand({
    required this.botUserId,
    required this.botUsername,
    required this.botDisplayName,
    required this.prefix,
    required this.name,
    required this.description,
    this.usage,
  });

  final String botUserId;
  final String botUsername;
  final String botDisplayName;

  /// What this bot answers to, e.g. `!` or `?`; never `/`, `@` or `:`.
  final String prefix;

  /// The bare keyword after [prefix]; the composer inserts `$prefix$name `.
  final String name;
  final String description;
  final String? usage;

  factory ChannelBotCommand.fromJson(Map<String, dynamic> json) =>
      ChannelBotCommand(
        botUserId: json['bot_user_id'] as String,
        botUsername: json['bot_username'] as String,
        botDisplayName: json['bot_display_name'] as String,
        prefix: json['prefix'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        usage: json['usage'] as String?,
      );
}

/// One entry of a bot's own registered set, from `GET /bots/{botId}/commands`.
class RegisteredBotCommand {
  const RegisteredBotCommand({
    required this.name,
    required this.description,
    this.usage,
  });

  final String name;
  final String description;
  final String? usage;

  factory RegisteredBotCommand.fromJson(Map<String, dynamic> json) =>
      RegisteredBotCommand(
        name: json['name'] as String,
        description: json['description'] as String,
        usage: json['usage'] as String?,
      );
}

/// A bot's whole registration, for its profile. Null [prefix] means it has
/// never registered anything.
class BotCommandRegistration {
  const BotCommandRegistration({required this.prefix, required this.commands});

  final String? prefix;
  final List<RegisteredBotCommand> commands;

  factory BotCommandRegistration.fromJson(Map<String, dynamic> json) =>
      BotCommandRegistration(
        prefix: json['prefix'] as String?,
        commands: (json['commands'] as List<dynamic>)
            .map(
                (c) => RegisteredBotCommand.fromJson(c as Map<String, dynamic>))
            .toList(growable: false),
      );
}
