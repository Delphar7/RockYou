import Foundation

/// Deterministic 64-bit hash for stable visual seeding (e.g. texture cropping).
///
/// Note: This is *not* cryptographic. It's intentionally stable across runs and platforms.
extension String {
  /// 64-bit FNV-1a over UTF-8 bytes.
  var stableHash64: UInt64 {
    let fnvOffset: UInt64 = 0xcbf29ce484222325
    let fnvPrime: UInt64 = 0x100000001b3
    var hash = fnvOffset
    for b in utf8 {
      hash ^= UInt64(b)
      hash &*= fnvPrime
    }
    return hash
  }
}
