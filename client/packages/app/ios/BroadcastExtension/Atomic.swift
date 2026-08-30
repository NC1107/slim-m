// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
// Adapted from the LiveKit Flutter example's broadcast extension, which took
// it in turn from Maksym Shcheglov's atomic property wrapper.
import Foundation

/// A lock-guarded property. `SampleUploader.isReady` is written from the
/// ReplayKit callback thread and read from the upload queue.
@propertyWrapper
struct Atomic<Value> {
  private var value: Value
  private let lock = NSLock()

  init(wrappedValue value: Value) {
    self.value = value
  }

  var wrappedValue: Value {
    get { load() }
    set { store(newValue: newValue) }
  }

  func load() -> Value {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  mutating func store(newValue: Value) {
    lock.lock()
    defer { lock.unlock() }
    value = newValue
  }
}
