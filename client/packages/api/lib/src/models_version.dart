// SPDX-License-Identifier: Apache-2.0
/// What a server says about itself before anyone signs in: its build, the
/// protocol it speaks, what it can do, and the identity a client pins.

import 'models_identity.dart';

/// What a server says about the safety tools slim-m's model depends on.
///
/// [unknown] is not [missing]. A server too old to advertise anything has not
/// said it has no report or block; accusing it of that would be a lie the
/// client made up, and the two states read differently to the user for that
/// reason.
enum SafetyTools { present, missing, unknown }

/// The two capabilities slim-m's safety model is made of. Reporting is how a
/// person reaches a human; blocking is what they can do without one.
const safetyCapabilities = <String>['report', 'block'];

/// The server's identity and negotiated protocol version.
class Version {
  const Version({
    required this.name,
    required this.version,
    required this.protocol,
    this.pushEnabled,
    this.inviteRequired,
    this.capabilities,
    this.identity,
  });

  final String name;
  final String version;
  final int protocol;

  /// Whether the server can deliver push notifications at all. Null on
  /// servers too old to report it, which is "unknown", not "no": warning
  /// someone off a server that actually has push would be worse than
  /// staying quiet.
  final bool? pushEnabled;

  /// Whether creating an account here needs an invite code. Null on servers
  /// older than 0.14.2, which is "unknown": the sign-up screen stays quiet
  /// rather than promising either way.
  final bool? inviteRequired;

  /// The optional features the server serves, by name. Null on servers older
  /// than 0.17.0, which is "unknown", not "none".
  final List<String>? capabilities;

  /// The server's trust-on-first-use identity. Null on servers too old to
  /// report it, the same "unknown" treatment [pushEnabled] gets.
  final ServerIdentity? identity;

  /// Whether this server offers reporting and blocking at all.
  SafetyTools get safetyTools => capabilities == null
      ? SafetyTools.unknown
      : missingSafetyTools.isEmpty
          ? SafetyTools.present
          : SafetyTools.missing;

  /// The names in [safetyCapabilities] this server does not advertise, in that
  /// list's order. Also empty on a server that advertised nothing at all, so
  /// read [safetyTools] before this to tell those apart.
  List<String> get missingSafetyTools {
    final advertised = capabilities;
    if (advertised == null) return const [];
    return safetyCapabilities
        .where((name) => !advertised.contains(name))
        .toList(growable: false);
  }

  factory Version.fromJson(Map<String, dynamic> json) => Version(
        name: json['name'] as String,
        version: json['version'] as String,
        protocol: json['protocol'] as int,
        pushEnabled: json['push_enabled'] as bool?,
        inviteRequired: json['invite_required'] as bool?,
        // A non-list here is a foreign or broken server, which is unknown
        // rather than a reason to crash sign-in.
        capabilities: switch (json['capabilities']) {
          final List<dynamic> names => names.whereType<String>().toList(
                growable: false,
              ),
          _ => null,
        },
        identity: json['identity'] == null
            ? null
            : ServerIdentity.fromJson(json['identity'] as Map<String, dynamic>),
      );
}
