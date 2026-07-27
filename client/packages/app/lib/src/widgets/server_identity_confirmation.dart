// SPDX-License-Identifier: Apache-2.0
/// The orchestration behind the manual "connect to a server" flow's identity
/// step: probing `/version`, comparing against whatever this app already
/// pinned for that address, and deciding which of the two identity screens
/// (if either) a human needs to see before onboarding can proceed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import '../providers/providers.dart';
import 'server_fingerprint_step.dart';
import 'server_identity_changed_step.dart';

/// The handle a server's pinned public key is stored under, one per address:
/// a session token is per-account, but this is a property of the address
/// itself and must survive across every account ever signed into it.
String _identityHandle(Uri address) => 'server_identity:${address.origin}';

/// Probes the chosen address's identity and pins it, trust-on-first-use
/// style: silent when it matches what is already pinned, an explicit step
/// the first time there is nothing to compare against, and a hard stop that
/// needs deliberate acknowledgement if it ever changes.
///
/// Returns whether it is safe to continue with [server]. A server too old to
/// report an identity, or unreachable here, is treated as unknown rather than
/// blocked: sign-in surfaces a real connection failure with more authority
/// than a probe run during onboarding ever could.
Future<bool> confirmServerIdentity(
  BuildContext context,
  WidgetRef ref,
  Uri server,
) async {
  final client = ref.read(probeApiProvider)(server);
  api.ServerIdentity? identity;
  try {
    identity = (await client.version()).identity;
  } catch (_) {
    return true;
  } finally {
    client.close();
  }
  if (identity == null) return true;
  if (!context.mounted) return false;

  final keyStore = ref.read(keyStoreProvider);
  final handle = _identityHandle(server);
  final pinned = await keyStore.read(handle);

  if (pinned == identity.publicKey) return true;
  if (!context.mounted) return false;

  final trusted = pinned == null
      ? await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) =>
                ServerFingerprintStep(address: server, identity: identity!),
          ),
        )
      : await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) =>
                ServerIdentityChangedStep(address: server, identity: identity!),
          ),
        );

  if (trusted != true) return false;
  await keyStore.put(handle, identity.publicKey);
  return true;
}
