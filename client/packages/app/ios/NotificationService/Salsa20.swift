// SPDX-License-Identifier: Apache-2.0
//
// Salsa20/20's core, the HSalsa20 key derivation built on it, and the
// keystream a sealed box's XSalsa20 half needs.
//
// CryptoKit has ChaCha20-Poly1305 and nothing in the Salsa family, and the
// sealed box this app has to open is the libsodium one. See
// PushSealedBox.swift.

import Foundation

enum Salsa20 {
  /// "expand 32-byte k", as four little-endian words.
  private static let sigma: [UInt32] = [
    0x6170_7865, 0x3320_646e, 0x7962_2d32, 0x6b20_6574,
  ]

  private static let blockBytes = 64

  /// HSalsa20: 20 rounds over key and a 16-byte input, with no feed-forward,
  /// keeping the eight words the specification names. Used twice by a sealed
  /// box - once to turn the X25519 shared secret into the box key, once to
  /// turn the box key plus the nonce's first half into the stream key.
  static func hsalsa20(key: [UInt8], input16: [UInt8]) -> [UInt8] {
    precondition(key.count == 32 && input16.count == 16)

    var state = [UInt32](repeating: 0, count: 16)
    state[0] = sigma[0]
    state[5] = sigma[1]
    state[10] = sigma[2]
    state[15] = sigma[3]
    for i in 0..<4 {
      state[1 + i] = littleEndian32(key, at: i * 4)
      state[11 + i] = littleEndian32(key, at: 16 + i * 4)
      state[6 + i] = littleEndian32(input16, at: i * 4)
    }

    let mixed = rounds(state)
    // Not state[0...8]: the words kept are the four constants' positions
    // and the four input words, which is what makes the result a key
    // rather than a truncated block.
    let kept = [mixed[0], mixed[5], mixed[10], mixed[15],
          mixed[6], mixed[7], mixed[8], mixed[9]]

    var out = [UInt8]()
    out.reserveCapacity(32)
    for word in kept {
      for shift in stride(from: 0, to: 32, by: 8) {
        out.append(UInt8(truncatingIfNeeded: word >> UInt32(shift)))
      }
    }
    return out
  }

  /// `count` bytes of the Salsa20/20 keystream starting at byte `offset`.
  ///
  /// An offset rather than a block index because the caller genuinely needs
  /// one: a secret box spends the first 32 bytes of block 0 on the one-time
  /// Poly1305 key and starts the message at byte 32, halfway through that
  /// same block, so anything that could only start at a block boundary
  /// would be wrong by exactly the bug this shape avoids.
  static func keystream(key: [UInt8], iv8: [UInt8], offset: Int, count: Int) -> [UInt8] {
    precondition(key.count == 32 && iv8.count == 8)
    precondition(offset >= 0 && count >= 0)
    guard count > 0 else { return [] }

    var out = [UInt8]()
    out.reserveCapacity(count)
    var position = offset
    while out.count < count {
      let blockIndex = UInt64(position / blockBytes)
      let within = position % blockBytes
      let block = keystreamBlock(key: key, iv8: iv8, counter: blockIndex)
      let take = min(blockBytes - within, count - out.count)
      out.append(contentsOf: block[within..<(within + take)])
      position += take
    }
    return out
  }

  private static func keystreamBlock(key: [UInt8], iv8: [UInt8], counter: UInt64) -> [UInt8] {
    var state = [UInt32](repeating: 0, count: 16)
    state[0] = sigma[0]
    state[5] = sigma[1]
    state[10] = sigma[2]
    state[15] = sigma[3]
    for i in 0..<4 {
      state[1 + i] = littleEndian32(key, at: i * 4)
      state[11 + i] = littleEndian32(key, at: 16 + i * 4)
    }
    state[6] = littleEndian32(iv8, at: 0)
    state[7] = littleEndian32(iv8, at: 4)
    state[8] = UInt32(truncatingIfNeeded: counter)
    state[9] = UInt32(truncatingIfNeeded: counter >> 32)

    var mixed = rounds(state)
    // The feed-forward that HSalsa20 deliberately omits.
    for i in 0..<16 {
      mixed[i] = mixed[i] &+ state[i]
    }

    var block = [UInt8]()
    block.reserveCapacity(blockBytes)
    for word in mixed {
      for shift in stride(from: 0, to: 32, by: 8) {
        block.append(UInt8(truncatingIfNeeded: word >> UInt32(shift)))
      }
    }
    return block
  }

  /// Ten double rounds - four columns then four rows each - which is what
  /// "Salsa20/20" counts as twenty.
  private static func rounds(_ input: [UInt32]) -> [UInt32] {
    var x = input
    for _ in 0..<10 {
      // Columns.
      quarter(&x, 0, 4, 8, 12)
      quarter(&x, 5, 9, 13, 1)
      quarter(&x, 10, 14, 2, 6)
      quarter(&x, 15, 3, 7, 11)
      // Rows.
      quarter(&x, 0, 1, 2, 3)
      quarter(&x, 5, 6, 7, 4)
      quarter(&x, 10, 11, 8, 9)
      quarter(&x, 15, 12, 13, 14)
    }
    return x
  }

  /// One quarter-round over four indices, in the specification's own order.
  /// The four rotations are fixed by position within the round, so they are
  /// written here literally rather than tracked anywhere.
  ///
  /// Each step reads into a local before assigning rather than using `^=`
  /// directly: a compound assignment into one element of an `inout` array
  /// while the same array is being read on the right is an overlapping
  /// access, and there is no reason to find out the hard way which side of
  /// Swift's exclusivity rules it lands on.
  private static func quarter(_ x: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
    let first = rotateLeft(x[a] &+ x[d], 7)
    x[b] = x[b] ^ first
    let second = rotateLeft(x[b] &+ x[a], 9)
    x[c] = x[c] ^ second
    let third = rotateLeft(x[c] &+ x[b], 13)
    x[d] = x[d] ^ third
    let fourth = rotateLeft(x[d] &+ x[c], 18)
    x[a] = x[a] ^ fourth
  }

  private static func rotateLeft(_ value: UInt32, _ bits: UInt32) -> UInt32 {
    (value << bits) | (value >> (32 - bits))
  }

  private static func littleEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    var word: UInt32 = 0
    for i in 0..<4 {
      word |= UInt32(bytes[offset + i]) << UInt32(i * 8)
    }
    return word
  }
}
