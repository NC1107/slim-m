// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// Reading the push private key the app generated, from this separate process.
//
// The attributes below are not a choice made here: they have to match, exactly
// and attribute for attribute, what flutter_secure_storage wrote on the app's
// side, because a keychain query is a search over attributes and any one of
// them being different simply finds nothing. See
// client/packages/platform/lib/src/persistent_key_store.dart, whose
// `SecureKeyStore.forPushKey` is the other half, and the hygiene workflow,
// which fails when the two disagree.

import Foundation
import Security

enum PushKeychain {
  /// Shared with the app through both binaries' `keychain-access-groups`.
  /// Deliberately not the app's own default group: the only thing this
  /// process needs is the push key, and this group holds nothing else.
  static let accessGroup = "76S78SUWVM.top.npcserver.slimm.push"

  /// `DevicePushKeys`' storage handle, which flutter_secure_storage maps to
  /// `kSecAttrAccount`.
  static let account = "push_x25519_private_key"

  /// flutter_secure_storage's own default `accountName`, which it maps to
  /// `kSecAttrService`. Not configured on the Dart side, so changing it
  /// there would silently orphan this read.
  static let service = "flutter_secure_storage_service"

  private static let seedBytes = 32

  /// The raw 32-byte X25519 private key, or nil when it has not been
  /// generated yet, the phone has not been unlocked since boot, or anything
  /// else went wrong. Every one of those is "show the generic string", so
  /// they are deliberately not told apart.
  ///
  /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` is the whole reason
  /// this can answer at all: the app's other secrets are stored
  /// `WhenUnlocked`, which is unreadable on a locked screen - exactly when a
  /// lock-screen preview is being built.
  static func privateKey() -> [UInt8]? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrAccount: account,
      kSecAttrService: service,
      kSecAttrAccessGroup: accessGroup,
      kSecAttrSynchronizable: false,
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecMatchLimit: kSecMatchLimitOne,
      kSecReturnData: true,
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let stored = item as? Data else { return nil }

    // Stored as text, because flutter_secure_storage only holds strings:
    // the value is the base64 of the seed, not the seed itself.
    guard let encoded = String(data: stored, encoding: .utf8),
      let seed = Data(base64Encoded: encoded),
      seed.count == seedBytes
    else { return nil }

    return [UInt8](seed)
  }
}
