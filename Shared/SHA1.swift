import CommonCrypto
import Foundation

enum SHA1 {
  static func digest(_ data: Data) -> Data {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
    data.withUnsafeBytes { bytes in
      _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &digest)
    }
    return Data(digest)
  }

  static func hex(_ data: Data) -> String {
    digest(data).map { String(format: "%02x", $0) }.joined()
  }
}
