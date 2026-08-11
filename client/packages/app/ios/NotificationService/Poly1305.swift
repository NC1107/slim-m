// SPDX-License-Identifier: Apache-2.0
//
// Poly1305 one-time authenticator, in the original NaCl form a secret box
// uses: the tag covers the ciphertext alone, with no associated data and no
// length block, and a partial final block is padded with a single 1 byte.
//
// The limb arithmetic follows poly1305-donna's 32-bit variant word for word,
// including where it truncates on purpose, because matching a reference
// implementation exactly is the only way to be sure of a carry chain nobody
// here can run against a device. RunnerTests/PushSealedBoxTests.swift checks
// it against tags a real server produced.

import Foundation

enum Poly1305 {
  private static let tagBytes = 16

  /// The 16-byte tag for `message` under a 32-byte one-time key.
  static func authenticate(message: [UInt8], key: [UInt8]) -> [UInt8] {
    precondition(key.count == 32)

    // r, clamped: the mask constants are the clamp and the limb split in
    // one, which is why they are not all 0x3ffffff.
    let t0 = littleEndian32(key, at: 0)
    let t1 = littleEndian32(key, at: 4)
    let t2 = littleEndian32(key, at: 8)
    let t3 = littleEndian32(key, at: 12)

    let r0 = t0 & 0x3ff_ffff
    let r1 = ((t0 >> 26) | (t1 << 6)) & 0x3ff_ff03
    let r2 = ((t1 >> 20) | (t2 << 12)) & 0x3ff_c0ff
    let r3 = ((t2 >> 14) | (t3 << 18)) & 0x3f0_3fff
    let r4 = (t3 >> 8) & 0x00f_ffff

    let s1 = r1 &* 5
    let s2 = r2 &* 5
    let s3 = r3 &* 5
    let s4 = r4 &* 5

    var h = [UInt32](repeating: 0, count: 5)

    func absorb(_ block: [UInt8], highBit: UInt32) {
      let b0 = littleEndian32(block, at: 0)
      let b1 = littleEndian32(block, at: 4)
      let b2 = littleEndian32(block, at: 8)
      let b3 = littleEndian32(block, at: 12)

      h[0] = h[0] &+ (b0 & 0x3ff_ffff)
      h[1] = h[1] &+ (((b0 >> 26) | (b1 << 6)) & 0x3ff_ffff)
      h[2] = h[2] &+ (((b1 >> 20) | (b2 << 12)) & 0x3ff_ffff)
      h[3] = h[3] &+ (((b2 >> 14) | (b3 << 18)) & 0x3ff_ffff)
      h[4] = h[4] &+ ((b3 >> 8) | highBit)

      let d0 = UInt64(h[0]) * UInt64(r0) + UInt64(h[1]) * UInt64(s4)
        + UInt64(h[2]) * UInt64(s3) + UInt64(h[3]) * UInt64(s2)
        + UInt64(h[4]) * UInt64(s1)
      var d1 = UInt64(h[0]) * UInt64(r1) + UInt64(h[1]) * UInt64(r0)
        + UInt64(h[2]) * UInt64(s4) + UInt64(h[3]) * UInt64(s3)
        + UInt64(h[4]) * UInt64(s2)
      var d2 = UInt64(h[0]) * UInt64(r2) + UInt64(h[1]) * UInt64(r1)
        + UInt64(h[2]) * UInt64(r0) + UInt64(h[3]) * UInt64(s4)
        + UInt64(h[4]) * UInt64(s3)
      var d3 = UInt64(h[0]) * UInt64(r3) + UInt64(h[1]) * UInt64(r2)
        + UInt64(h[2]) * UInt64(r1) + UInt64(h[3]) * UInt64(r0)
        + UInt64(h[4]) * UInt64(s4)
      var d4 = UInt64(h[0]) * UInt64(r4) + UInt64(h[1]) * UInt64(r3)
        + UInt64(h[2]) * UInt64(r2) + UInt64(h[3]) * UInt64(r1)
        + UInt64(h[4]) * UInt64(r0)

      var carry = UInt32(truncatingIfNeeded: d0 >> 26)
      h[0] = UInt32(truncatingIfNeeded: d0) & 0x3ff_ffff
      d1 &+= UInt64(carry)
      carry = UInt32(truncatingIfNeeded: d1 >> 26)
      h[1] = UInt32(truncatingIfNeeded: d1) & 0x3ff_ffff
      d2 &+= UInt64(carry)
      carry = UInt32(truncatingIfNeeded: d2 >> 26)
      h[2] = UInt32(truncatingIfNeeded: d2) & 0x3ff_ffff
      d3 &+= UInt64(carry)
      carry = UInt32(truncatingIfNeeded: d3 >> 26)
      h[3] = UInt32(truncatingIfNeeded: d3) & 0x3ff_ffff
      d4 &+= UInt64(carry)
      carry = UInt32(truncatingIfNeeded: d4 >> 26)
      h[4] = UInt32(truncatingIfNeeded: d4) & 0x3ff_ffff
      h[0] = h[0] &+ carry &* 5
      carry = h[0] >> 26
      h[0] &= 0x3ff_ffff
      h[1] = h[1] &+ carry
    }

    var offset = 0
    while message.count - offset >= tagBytes {
      absorb(Array(message[offset..<(offset + tagBytes)]), highBit: 1 << 24)
      offset += tagBytes
    }
    if offset < message.count {
      // The padding 1 goes immediately after the data, and the implicit
      // 2^128 bit is dropped for this block - that is what makes a short
      // final block unambiguous.
      var last = Array(message[offset...])
      last.append(1)
      last.append(contentsOf: [UInt8](repeating: 0, count: tagBytes - last.count))
      absorb(last, highBit: 0)
    }

    return finish(&h, pad: [
      littleEndian32(key, at: 16), littleEndian32(key, at: 20),
      littleEndian32(key, at: 24), littleEndian32(key, at: 28),
    ])
  }

  private static func finish(_ h: inout [UInt32], pad: [UInt32]) -> [UInt8] {
    var carry = h[1] >> 26
    h[1] &= 0x3ff_ffff
    h[2] = h[2] &+ carry
    carry = h[2] >> 26
    h[2] &= 0x3ff_ffff
    h[3] = h[3] &+ carry
    carry = h[3] >> 26
    h[3] &= 0x3ff_ffff
    h[4] = h[4] &+ carry
    carry = h[4] >> 26
    h[4] &= 0x3ff_ffff
    h[0] = h[0] &+ carry &* 5
    carry = h[0] >> 26
    h[0] &= 0x3ff_ffff
    h[1] = h[1] &+ carry

    // h + -p, kept only if it did not borrow, which is the branch-free way
    // of saying "reduce modulo 2^130 - 5 if it is at least that big".
    var g = [UInt32](repeating: 0, count: 5)
    g[0] = h[0] &+ 5
    carry = g[0] >> 26
    g[0] &= 0x3ff_ffff
    for i in 1..<4 {
      g[i] = h[i] &+ carry
      carry = g[i] >> 26
      g[i] &= 0x3ff_ffff
    }
    g[4] = h[4] &+ carry &- (1 << 26)

    var mask = (g[4] >> 31) &- 1
    for i in 0..<5 { g[i] &= mask }
    mask = ~mask
    for i in 0..<5 { h[i] = (h[i] & mask) | g[i] }

    // Back from five 26-bit limbs to four 32-bit words.
    var words = [UInt32](repeating: 0, count: 4)
    words[0] = (h[0] | (h[1] << 26))
    words[1] = ((h[1] >> 6) | (h[2] << 20))
    words[2] = ((h[2] >> 12) | (h[3] << 14))
    words[3] = ((h[3] >> 18) | (h[4] << 8))

    var running: UInt64 = 0
    for i in 0..<4 {
      running = UInt64(words[i]) &+ UInt64(pad[i]) &+ (running >> 32)
      words[i] = UInt32(truncatingIfNeeded: running)
    }

    var tag = [UInt8]()
    tag.reserveCapacity(tagBytes)
    for word in words {
      for shift in stride(from: 0, to: 32, by: 8) {
        tag.append(UInt8(truncatingIfNeeded: word >> UInt32(shift)))
      }
    }
    return tag
  }

  /// Compares in time that does not depend on where the first difference
  /// is. A tag check that returned early would leak the correct tag one byte
  /// at a time to anything able to retry.
  static func constantTimeEquals(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count else { return false }
    var difference: UInt8 = 0
    for i in 0..<a.count {
      difference |= a[i] ^ b[i]
    }
    return difference == 0
  }

  private static func littleEndian32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    var word: UInt32 = 0
    for i in 0..<4 {
      word |= UInt32(bytes[offset + i]) << UInt32(i * 8)
    }
    return word
  }
}
