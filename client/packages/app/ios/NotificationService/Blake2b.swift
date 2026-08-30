// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// BLAKE2b (RFC 7693), unkeyed, single-shot.
//
// Here to rebuild one thing: a sealed box's nonce is
// BLAKE2b(ephemeral_public || recipient_public) truncated to 24 bytes, and
// neither CryptoKit nor CommonCrypto has BLAKE2b at all. See
// PushSealedBox.swift for why this file exists rather than a dependency, and
// RunnerTests/PushSealedBoxTests.swift for the fixture that proves it right.

import Foundation

enum Blake2b {
  /// The SHA-512 initialisation vector, which BLAKE2b reuses (RFC 7693 2.6).
  private static let iv: [UInt64] = [
    0x6a09_e667_f3bc_c908, 0xbb67_ae85_84ca_a73b,
    0x3c6e_f372_fe94_f82b, 0xa54f_f53a_5f1d_36f1,
    0x510e_527f_ade6_82d1, 0x9b05_688c_2b3e_6c1f,
    0x1f83_d9ab_fb41_bd6b, 0x5be0_cd19_137e_2179,
  ]

  /// The message-word permutation, one row per round (RFC 7693 2.7). Rounds
  /// 10 and 11 repeat rows 0 and 1, which is the specification's own wrap
  /// rather than a copy-paste.
  private static let sigma: [[Int]] = [
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
    [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4],
    [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
    [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13],
    [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
    [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11],
    [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
    [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5],
    [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
    [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  ]

  private static let blockBytes = 128

  /// Hashes `message` to `digestLength` bytes, with no key, salt or
  /// personalisation - which is what libsodium's `crypto_generichash`
  /// defaults to, and so what the sealed box's nonce derivation uses.
  ///
  /// The byte counter is 128 bits in the specification and 64 here: an
  /// input at all near 2^64 bytes cannot be held to hash in the first
  /// place, and the only caller passes 64 bytes.
  static func hash(_ message: [UInt8], digestLength: Int) -> [UInt8] {
    precondition(digestLength > 0 && digestLength <= 64)

    var state = iv
    // The parameter block, folded into the first word: digest length in
    // byte 0, key length (zero) in byte 1, fanout and depth both 1.
    state[0] ^= 0x0101_0000 ^ UInt64(digestLength)

    var counter: UInt64 = 0
    var offset = 0
    // Strictly greater, never equal: the last full block has to be
    // compressed as the final one, with its own flag set.
    while message.count - offset > blockBytes {
      counter &+= UInt64(blockBytes)
      compress(
        &state,
        block: Array(message[offset..<(offset + blockBytes)]),
        counter: counter,
        isFinal: false
      )
      offset += blockBytes
    }

    var last = Array(message[offset...])
    counter &+= UInt64(last.count)
    last.append(contentsOf: [UInt8](repeating: 0, count: blockBytes - last.count))
    compress(&state, block: last, counter: counter, isFinal: true)

    var digest = [UInt8]()
    digest.reserveCapacity(digestLength)
    for word in state {
      for shift in stride(from: 0, to: 64, by: 8) {
        guard digest.count < digestLength else { return digest }
        digest.append(UInt8(truncatingIfNeeded: word >> UInt64(shift)))
      }
    }
    return digest
  }

  private static func compress(
    _ state: inout [UInt64],
    block: [UInt8],
    counter: UInt64,
    isFinal: Bool
  ) {
    var m = [UInt64](repeating: 0, count: 16)
    for i in 0..<16 {
      m[i] = littleEndian64(block, at: i * 8)
    }

    var v = [UInt64](repeating: 0, count: 16)
    for i in 0..<8 {
      v[i] = state[i]
      v[i + 8] = iv[i]
    }
    v[12] ^= counter
    // v[13] would take the counter's high half, always zero here.
    if isFinal { v[14] = ~v[14] }

    for round in 0..<12 {
      let s = sigma[round]
      mix(&v, 0, 4, 8, 12, m[s[0]], m[s[1]])
      mix(&v, 1, 5, 9, 13, m[s[2]], m[s[3]])
      mix(&v, 2, 6, 10, 14, m[s[4]], m[s[5]])
      mix(&v, 3, 7, 11, 15, m[s[6]], m[s[7]])
      mix(&v, 0, 5, 10, 15, m[s[8]], m[s[9]])
      mix(&v, 1, 6, 11, 12, m[s[10]], m[s[11]])
      mix(&v, 2, 7, 8, 13, m[s[12]], m[s[13]])
      mix(&v, 3, 4, 9, 14, m[s[14]], m[s[15]])
    }

    for i in 0..<8 {
      state[i] ^= v[i] ^ v[i + 8]
    }
  }

  private static func mix(
    _ v: inout [UInt64],
    _ a: Int, _ b: Int, _ c: Int, _ d: Int,
    _ x: UInt64, _ y: UInt64
  ) {
    v[a] = v[a] &+ v[b] &+ x
    v[d] = rotateRight(v[d] ^ v[a], 32)
    v[c] = v[c] &+ v[d]
    v[b] = rotateRight(v[b] ^ v[c], 24)
    v[a] = v[a] &+ v[b] &+ y
    v[d] = rotateRight(v[d] ^ v[a], 16)
    v[c] = v[c] &+ v[d]
    v[b] = rotateRight(v[b] ^ v[c], 63)
  }

  private static func rotateRight(_ value: UInt64, _ bits: UInt64) -> UInt64 {
    (value >> bits) | (value << (64 - bits))
  }

  private static func littleEndian64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
    var word: UInt64 = 0
    for i in 0..<8 {
      word |= UInt64(bytes[offset + i]) << UInt64(i * 8)
    }
    return word
  }
}
