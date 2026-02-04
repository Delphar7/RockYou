#!/usr/bin/env swift
import CryptoKit
import Foundation

enum ASCError: Error {
  case missingEnv(String)
  case invalidBundleId
  case invalidPrivateKey
  case requestFailed(String)
  case decodeFailed
}

func env(_ name: String) throws -> String {
  let value = ProcessInfo.processInfo.environment[name] ?? ""
  if value.isEmpty { throw ASCError.missingEnv(name) }
  return value
}

func base64url(_ data: Data) -> String {
  return data.base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")
}

func base64url(_ string: String) -> String {
  return base64url(Data(string.utf8))
}

func chunked(_ string: String, size: Int) -> String {
  var result: [String] = []
  var index = string.startIndex
  while index < string.endIndex {
    let nextIndex =
      string.index(index, offsetBy: size, limitedBy: string.endIndex) ?? string.endIndex
    result.append(String(string[index..<nextIndex]))
    index = nextIndex
  }
  return result.joined(separator: "\n")
}

func stripBase64(_ string: String) -> String {
  return string.filter { character in
    switch character {
    case "A"..."Z", "a"..."z", "0"..."9", "+", "/", "=":
      return true
    default:
      return false
    }
  }
}

func extractPEMBody(_ pem: String) -> (body: String, header: String, footer: String)? {
  let headerFooterPairs = [
    ("-----BEGIN PRIVATE KEY-----", "-----END PRIVATE KEY-----"),
    ("-----BEGIN EC PRIVATE KEY-----", "-----END EC PRIVATE KEY-----"),
  ]

  for (header, footer) in headerFooterPairs {
    guard let headerRange = pem.range(of: header) else { continue }
    guard let footerRange = pem.range(of: footer, range: headerRange.upperBound..<pem.endIndex)
    else { continue }
    let body = String(pem[headerRange.upperBound..<footerRange.lowerBound])
    return (body: body, header: header, footer: footer)
  }

  return nil
}

func privateKeyFromEnv(_ value: String) throws -> P256.Signing.PrivateKey {
  var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count > 1 {
    trimmed = String(trimmed.dropFirst().dropLast())
  }

  let normalized =
    trimmed
    .replacingOccurrences(of: "\\n", with: "\n")
    .replacingOccurrences(of: "\\r", with: "\r")

  if let extracted = extractPEMBody(normalized) {
    let base64Body = stripBase64(extracted.body)
    if let derData = Data(base64Encoded: base64Body) {
      do {
        return try P256.Signing.PrivateKey(derRepresentation: derData)
      } catch {
        let pem = "\(extracted.header)\n\(chunked(base64Body, size: 64))\n\(extracted.footer)"
        return try P256.Signing.PrivateKey(pemRepresentation: pem)
      }
    }
  }

  let base64 = stripBase64(normalized)
  guard let derData = Data(base64Encoded: base64) else {
    throw ASCError.invalidPrivateKey
  }

  do {
    return try P256.Signing.PrivateKey(derRepresentation: derData)
  } catch {
    let pem = "-----BEGIN PRIVATE KEY-----\n\(chunked(base64, size: 64))\n-----END PRIVATE KEY-----"
    return try P256.Signing.PrivateKey(pemRepresentation: pem)
  }
}

func makeJWT(issuerId: String, keyId: String, privateKey: P256.Signing.PrivateKey) throws -> String
{
  let header: [String: String] = [
    "alg": "ES256",
    "kid": keyId,
    "typ": "JWT",
  ]
  let payload: [String: Any] = [
    "iss": issuerId,
    "exp": Int(Date().addingTimeInterval(1200).timeIntervalSince1970),
    "aud": "appstoreconnect-v1",
  ]

  let headerData = try JSONSerialization.data(withJSONObject: header, options: [])
  let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
  let headerSegment = base64url(headerData)
  let payloadSegment = base64url(payloadData)
  let toSign = "\(headerSegment).\(payloadSegment)"
  let signature = try privateKey.signature(for: Data(toSign.utf8))
  let signatureSegment = base64url(signature.rawRepresentation)
  return "\(toSign).\(signatureSegment)"
}

func fetchJSON(url: URL, token: String) throws -> [String: Any] {
  var request = URLRequest(url: url)
  request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  request.addValue("application/json", forHTTPHeaderField: "Accept")

  let semaphore = DispatchSemaphore(value: 0)
  var responseData: Data?
  var responseError: Error?
  var statusCode: Int?

  URLSession.shared.dataTask(with: request) { data, response, error in
    responseData = data
    responseError = error
    statusCode = (response as? HTTPURLResponse)?.statusCode
    semaphore.signal()
  }.resume()

  semaphore.wait()

  if let error = responseError {
    throw ASCError.requestFailed(error.localizedDescription)
  }
  guard let statusCode, (200..<300).contains(statusCode) else {
    let body = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? "unknown"
    throw ASCError.requestFailed("HTTP \(statusCode ?? -1): \(body)")
  }
  guard let responseData,
    let json = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
  else {
    throw ASCError.decodeFailed
  }
  return json
}

func appId(for bundleId: String, token: String) throws -> String {
  guard !bundleId.isEmpty else { throw ASCError.invalidBundleId }
  let url = URL(
    string: "https://api.appstoreconnect.apple.com/v1/apps?filter[bundleId]=\(bundleId)&limit=1")!
  let json = try fetchJSON(url: url, token: token)
  let data = json["data"] as? [[String: Any]] ?? []
  guard let first = data.first, let id = first["id"] as? String else {
    throw ASCError.requestFailed("App not found for bundle id \(bundleId)")
  }
  return id
}

func latestBuildNumber(appId: String, token: String) throws -> Int {
  var maxVersion = 0
  var nextURL = URL(
    string:
      "https://api.appstoreconnect.apple.com/v1/builds?filter[app]=\(appId)&fields[builds]=version&limit=200&sort=-uploadedDate"
  )!
  var seen: Set<String> = []
  var pageCount = 0

  while true {
    if seen.contains(nextURL.absoluteString) { break }
    seen.insert(nextURL.absoluteString)
    pageCount += 1
    if pageCount > 20 { break }

    let json = try fetchJSON(url: nextURL, token: token)
    let data = json["data"] as? [[String: Any]] ?? []
    for item in data {
      if let attributes = item["attributes"] as? [String: Any],
        let version = attributes["version"] as? String,
        let intVersion = Int(version)
      {
        if intVersion > maxVersion { maxVersion = intVersion }
      }
    }

    guard let links = json["links"] as? [String: Any],
      let next = links["next"] as? String,
      let url = URL(string: next)
    else {
      break
    }
    nextURL = url
  }

  return maxVersion
}

do {
  let bundleId = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
  let issuerId = try env("ASC_ISSUER_ID")
  let keyId = try env("ASC_KEY_ID")
  let privateKeyValue = try env("ASC_PRIVATE_KEY")
  let privateKey = try privateKeyFromEnv(privateKeyValue)

  let token = try makeJWT(issuerId: issuerId, keyId: keyId, privateKey: privateKey)
  let appIdentifier = try appId(for: bundleId, token: token)
  let latest = try latestBuildNumber(appId: appIdentifier, token: token)
  print(latest + 1)
} catch {
  fputs("Xcode Cloud build number error: \(error)\n", stderr)
  exit(1)
}
