import Foundation

/// Cross-platform deep link parsing.
///
/// We intentionally treat iPhone + Watch as a single shipped pair (no back-compat),
/// so this schema can evolve freely.
public enum DeepLink: Equatable, Sendable {
  case selectDevice(deviceId: String, page: String?)

  public init?(url: URL) {
    guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    guard let scheme = comps.scheme?.lowercased(), scheme == "rockyou" else { return nil }

    let host = (comps.host ?? "").lowercased()
    let path = comps.path.lowercased()

    // Supported:
    // - rockyou://watch/select?deviceId=...&page=media
    // - rockyou://select?deviceId=...
    let isSelect =
      host == "select"
      || (host == "watch" && path == "/select")
      || (host == "watch" && path == "select") // defensive (some launchers drop the leading slash)

    guard isSelect else { return nil }

    let deviceId = (comps.queryItems ?? []).first(where: { $0.name == "deviceId" })?.value
    guard let deviceId, !deviceId.isEmpty else { return nil }
    let pageRaw = (comps.queryItems ?? []).first(where: { $0.name == "page" })?.value
    let page = pageRaw.flatMap { $0.isEmpty ? nil : $0 }
    self = .selectDevice(deviceId: deviceId, page: page)
  }
}
