// SPDX-License-Identifier: Apache-2.0
import XCTest

/// The evidence that the Notification Service Extension's hand-written
/// sealed-box implementation is right.
///
/// It is hand-written because CryptoKit has one of the five primitives a
/// libsodium sealed box needs (see PushSealedBox.swift for that reasoning),
/// and reasoning about crypto is not the same as running it. So this opens
/// real ciphertext: `push_envelope_cases.json` is written by
/// `crates/slimm-server/tests/push_envelope_fixture.rs` using the same
/// `crypto_box` version the server actually seals with, and a Rust test
/// asserts the same file still opens with the server's own crate. If the two
/// implementations ever disagree, one of the two fails.
///
/// The crypto sources are compiled into this test target as well as into the
/// extension, so nothing here reaches across a module boundary.
final class PushSealedBoxTests: XCTestCase {
  private struct Fixture: Decodable {
    struct Case: Decodable {
      let name: String
      let plaintext: String
      let sealedBase64: String

      enum CodingKeys: String, CodingKey {
        case name
        case plaintext
        case sealedBase64 = "sealed_base64"
      }
    }

    let recipientSecretKeyBase64: String
    let cases: [Case]

    enum CodingKeys: String, CodingKey {
      case recipientSecretKeyBase64 = "recipient_secret_key_base64"
      case cases
    }
  }

  private func loadFixture() throws -> Fixture {
    let bundle = Bundle(for: type(of: self))
    let url = try XCTUnwrap(
      bundle.url(forResource: "push_envelope_cases", withExtension: "json"),
      "push_envelope_cases.json is not in the test bundle's resources"
    )
    return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
  }

  private func privateKey(_ fixture: Fixture) throws -> [UInt8] {
    let decoded = try XCTUnwrap(Data(base64Encoded: fixture.recipientSecretKeyBase64))
    return [UInt8](decoded)
  }

  /// The whole point. Every case, including the ones chosen for where the
  /// keystream crosses a block boundary rather than for realism.
  func testOpensEveryEnvelopeTheServerSealed() throws {
    let fixture = try loadFixture()
    let key = try privateKey(fixture)
    XCTAssertFalse(fixture.cases.isEmpty, "an empty fixture would pass vacuously")

    for testCase in fixture.cases {
      let sealed = try XCTUnwrap(
        Data(base64Encoded: testCase.sealedBase64),
        "\(testCase.name): sealed_base64 is not base64"
      )
      let opened = try XCTUnwrap(
        PushSealedBox.open([UInt8](sealed), privateKey: key),
        "\(testCase.name): did not open"
      )
      XCTAssertEqual(
        String(decoding: opened, as: UTF8.self),
        testCase.plaintext,
        "\(testCase.name): opened to the wrong plaintext"
      )
    }
  }

  /// A tag check that passed on modified ciphertext would be worse than no
  /// tag check, so this flips one bit of every byte position in turn on the
  /// smallest non-empty case and asserts each is refused.
  func testRefusesTamperedCiphertext() throws {
    let fixture = try loadFixture()
    let key = try privateKey(fixture)
    let testCase = try XCTUnwrap(fixture.cases.first { !$0.plaintext.isEmpty })
    let original = [UInt8](try XCTUnwrap(Data(base64Encoded: testCase.sealedBase64)))

    for index in 0..<original.count {
      var tampered = original
      tampered[index] ^= 0x01
      XCTAssertNil(
        PushSealedBox.open(tampered, privateKey: key),
        "\(testCase.name): byte \(index) was changed and it opened anyway"
      )
    }
  }

  /// Sealed to somebody else, which is what every notification for another
  /// device on the same relay is.
  func testRefusesAnEnvelopeSealedToAnotherKey() throws {
    let fixture = try loadFixture()
    var other = try privateKey(fixture)
    other[0] ^= 0xff
    let testCase = try XCTUnwrap(fixture.cases.first)
    let sealed = [UInt8](try XCTUnwrap(Data(base64Encoded: testCase.sealedBase64)))

    XCTAssertNil(PushSealedBox.open(sealed, privateKey: other))
  }

  /// Truncation must be refused rather than read past. A sealed box shorter
  /// than its own ephemeral key and tag has no ciphertext at all, and the
  /// empty case is exactly that length, so the boundary is real.
  func testRefusesTruncatedInput() throws {
    let fixture = try loadFixture()
    let key = try privateKey(fixture)

    for length in 0..<48 {
      XCTAssertNil(
        PushSealedBox.open([UInt8](repeating: 0, count: length), privateKey: key),
        "a \(length)-byte input is too short to be a sealed box"
      )
    }
  }

  /// BLAKE2b against RFC 7693's own appendix A vector, so a nonce that came
  /// out wrong points at the hash rather than at the whole construction.
  func testBlake2bMatchesTheSpecificationVector() {
    let digest = Blake2b.hash(Array("abc".utf8), digestLength: 64)
    let expected =
      "ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d1"
      + "7d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923"
    XCTAssertEqual(hex(digest), expected)
  }

  /// The 24-byte digest length the sealed box actually uses, which is a
  /// different parameter block from the 64-byte one above and so a genuinely
  /// separate case rather than a prefix of it.
  func testBlake2bTruncatedDigestIsNotJustAPrefix() {
    let short = Blake2b.hash(Array("abc".utf8), digestLength: 24)
    let long = Blake2b.hash(Array("abc".utf8), digestLength: 64)
    XCTAssertEqual(short.count, 24)
    XCTAssertNotEqual(short, Array(long[0..<24]))
  }

  private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
  }
}
