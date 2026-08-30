// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A server's long-lived, trust-on-first-use identity, carried on [Version].
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

/// A server's long-lived identity, pinned by a client on first connect and
/// meant to be compared on every one after, so a later machine-in-the-middle
/// changes the fingerprint visibly instead of silently. The client is the
/// half that has to hold up its end: it must bind that comparison to every
/// explicit connect, not merely to the address being typed.
///
/// This protects nothing about the very first connection: a client with
/// nothing pinned yet cannot tell a faithful server from an attacker's own
/// keypair, which is why onboarding has a human read the fingerprint aloud
/// for comparison rather than trusting it silently on that first connect.
class ServerIdentity {
  const ServerIdentity({
    required this.publicKey,
    required this.fingerprint,
    required this.fingerprintGroups,
    required this.colorStrip,
  });

  /// Standard base64 of the 32 raw Ed25519 public-key bytes. This, not
  /// [fingerprint], is what a client pins and compares byte-for-byte.
  final String publicKey;

  /// 32 lowercase hex characters (a truncated SHA-256 of the public key),
  /// with no separators.
  final String fingerprint;

  /// The same fingerprint as eight 4-character hex groups, for reading aloud.
  final List<String> fingerprintGroups;

  /// Four indices, each 0-5, into the client's six-entry cursor colour
  /// palette, deterministically derived from the fingerprint.
  final List<int> colorStrip;

  factory ServerIdentity.fromJson(Map<String, dynamic> json) => ServerIdentity(
        publicKey: json['public_key'] as String,
        fingerprint: json['fingerprint'] as String,
        fingerprintGroups:
            (json['fingerprint_groups'] as List<dynamic>).cast<String>(),
        colorStrip: (json['color_strip'] as List<dynamic>).cast<int>(),
      );
}
