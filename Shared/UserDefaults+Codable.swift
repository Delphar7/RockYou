import Foundation

extension UserDefaults {
  func decoded<T: Decodable>(_ type: T.Type = T.self, forKey key: String) -> T? {
    guard let data = data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
  }

  func setEncoded<T: Encodable>(_ value: T, forKey key: String) {
    guard let data = try? JSONEncoder().encode(value) else { return }
    set(data, forKey: key)
  }

  func setEncoded<T: Encodable>(_ value: T?, forKey key: String) {
    guard let value else {
      removeObject(forKey: key)
      return
    }
    setEncoded(value, forKey: key)
  }
}
