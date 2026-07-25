// SPDX-License-Identifier: Apache-2.0
/// This device's push-encryption keypair.
///
/// The server seals a content-free push envelope to the device's public key;
/// the private key never leaves the device. Nothing on it can open that
/// envelope yet (the Notification Service Extension is a later piece of
/// work), so today's whole job is generating the pair once and making it
/// survive restarts: a device that registered a new key on every launch would
/// orphan every envelope already sealed to the one before it.
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'key_store.dart';

/// The handle the private key is stored under. Exposed so tests and callers
/// sharing a [KeyStore] with other secrets do not need to guess it.
const devicePushKeyHandle = 'push_x25519_private_key';

/// Generates, persists, and reuses this device's X25519 keypair.
class DevicePushKeys {
  DevicePushKeys(this._keyStore, {String handle = devicePushKeyHandle})
      : _handle = handle;

  final KeyStore _keyStore;
  final String _handle;
  static final _algorithm = X25519();

  /// This device's public key, base64-encoded the way `PUT /push` expects it.
  /// Generates and persists a keypair the first time this is called; every
  /// later call, including after a restart, reuses the stored one.
  Future<String> publicKeyBase64() async {
    final keyPair = await _loadOrCreate();
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  Future<SimpleKeyPair> _loadOrCreate() async {
    final stored = await _keyStore.read(_handle);
    if (stored != null) {
      return _algorithm.newKeyPairFromSeed(base64Decode(stored));
    }

    final keyPair = await _algorithm.newKeyPair();
    final seed = await keyPair.extractPrivateKeyBytes();
    await _keyStore.put(_handle, base64Encode(seed));
    return keyPair;
  }
}
