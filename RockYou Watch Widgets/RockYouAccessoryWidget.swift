import SwiftUI
import WidgetKit

private let rockYouPurple = Color(
  red: 108.0 / 255.0,
  green: 64.0 / 255.0,
  blue: 159.0 / 255.0
)

private struct RockYouEntry: TimelineEntry {
  let date: Date
  let target: WatchComplicationTarget?
}

private struct RockYouProvider: TimelineProvider {
  func placeholder(in context: Context) -> RockYouEntry {
    RockYouEntry(date: Date(), target: nil)
  }

  func getSnapshot(in context: Context, completion: @escaping (RockYouEntry) -> Void) {
    completion(currentEntry())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<RockYouEntry>) -> Void) {
    // We rely on explicit `WidgetCenter.reloadAllTimelines()` from the watch app when updates arrive.
    let entry = currentEntry()
    completion(Timeline(entries: [entry], policy: .never))
  }

  private func currentEntry() -> RockYouEntry {
    guard let snapshot = WatchSurfaceSnapshotStore.loadSnapshot() else {
      return RockYouEntry(date: Date(), target: nil)
    }

    let target = WatchComplicationTargetPicker.pick(
      snapshot: snapshot,
      lastActiveDeviceId: WatchSurfaceSnapshotStore.lastActiveDeviceId
    )
    return RockYouEntry(date: Date(), target: target)
  }
}

struct RockYouAccessoryWidget: Widget {
  let kind = "RockYouAccessoryWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: RockYouProvider()) { entry in
      RockYouAccessoryWidgetView(entry: entry)
    }
    .configurationDisplayName("RockYou")
    .description("Quick status and launch for your Roku devices.")
    .supportedFamilies([
      .accessoryInline,
      .accessoryCircular,
      .accessoryCorner,
      .accessoryRectangular,
    ])
  }
}

private struct RockYouAccessoryWidgetView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.widgetRenderingMode) private var widgetRenderingMode

  let entry: RockYouEntry

  var body: some View {
    switch family {
    case .accessoryInline:
      inline
    case .accessoryCircular:
      circular
    case .accessoryCorner:
      corner
    case .accessoryRectangular:
      rectangular
    default:
      rectangular
    }
  }

  private var deviceName: String {
    entry.target?.deviceName ?? "RockYou"
  }

  private var statusColor: Color {
    switch entry.target?.powerMode ?? .unknown {
    case .on:
      return .green
    case .ready:
      return .orange
    case .off, .displayOff:
      return .red
    case .unknown:
      return .gray
    }
  }

  private var iconScreenColor: Color {
    // Per your preference:
    // - Full color: fill the "screen" with true status color.
    // - Accented/vibrant: let the face tint do its thing; keep it subdued.
    if widgetRenderingMode == .fullColor {
      return statusColor
    } else {
      return Color.white.opacity(0.12)
    }
  }

  private var deepLinkURL: URL? {
    guard let target = entry.target else { return nil }
    // Prefer media as the default “quick control” surface.
    var comps = URLComponents()
    comps.scheme = "rockyou"
    comps.host = "watch"
    comps.path = "/select"
    comps.queryItems = [
      URLQueryItem(name: "deviceId", value: target.deviceId),
      URLQueryItem(name: "page", value: "media"),
    ]
    return comps.url
  }

  private var inline: some View {
    let text = entry.target?.deviceName ?? "RockYou"
    return Group {
      if let url = deepLinkURL {
        Link(text, destination: url)
      } else {
        Text(text)
      }
    }
  }

  private var circular: some View {
    let content = ZStack {
      AccessoryWidgetBackground()
      RokuTVIcon(size: 26, screenColor: iconScreenColor)
        .widgetAccentable()
    }
    .widgetLabel {
      // Shows on faces/slots that surface the circular widget label (e.g. Infograph bezel).
      Text(deviceName)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    return Group {
      if let url = deepLinkURL {
        Link(destination: url) { content }
      } else {
        content
      }
    }
  }

  private var corner: some View {
    // Corner complications are “accessory” widgets too; keep it simple + high contrast.
    let content = ZStack {
      AccessoryWidgetBackground()
      RokuTVIcon(size: 22, screenColor: iconScreenColor)
        .widgetAccentable()
    }
    .widgetAccentable()
    .widgetLabel {
      // Curved label on many corner slots (including Color face corners).
      Text(deviceName)
    }

    return Group {
      if let url = deepLinkURL {
        Link(destination: url) { content }
      } else {
        content
      }
    }
  }

  private var rectangular: some View {
    let title = entry.target?.deviceName ?? "No devices"
    let subtitle: String = {
      guard let target = entry.target else { return "Open RockYou on iPhone" }
      switch target.priority {
      case .singleOnWithActiveApp: return "On • Active"
      case .singleOn: return "On"
      case .lastActive: return "Last used"
      case .firstAvailable: return "Available"
      }
    }()

    let content = HStack(spacing: 8) {
      RokuTVIcon(size: 18, screenColor: iconScreenColor)
        .widgetAccentable()
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
        Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer(minLength: 0)
      rightSideIcon
    }

    return Group {
      if let url = deepLinkURL {
        Link(destination: url) { content }
      } else {
        content
      }
    }
  }

  @ViewBuilder
  private var rightSideIcon: some View {
    switch entry.target?.iconHint {
    case let .channel(appId: appId):
      let deviceId = entry.target?.deviceId ?? ""
      if let image = WidgetAppIconDiskCache.iconImage(appId: appId, deviceId: deviceId) {
        WidgetIconTile(image: image, size: 24, cornerRadius: 6)
      } else {
        RockYouMarkTile(size: 24)
      }

    case .rokuDevice, .none:
      RockYouMarkTile(size: 24)
    }
  }
}

private enum WidgetAppIconDiskCache {
  static func iconImage(appId: String, deviceId: String) -> Image? {
    guard !appId.isEmpty, !deviceId.isEmpty else { return nil }
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else { return nil }

    let iconDir = appSupport.appendingPathComponent("AppIcons", isDirectory: true)
    let app = RokuApp(id: appId, name: "", type: nil, version: nil)
    let fileURL = iconDir.appendingPathComponent(app.iconFilename(for: deviceId))

    guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
    return PlatformImage.cachedContentsOfFile(fileURL.path)
  }
}

private struct WidgetIconTile: View {
  let image: Image
  let size: CGFloat
  let cornerRadius: CGFloat

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    image
      .resizable()
      .aspectRatio(contentMode: .fill)
      .frame(width: size, height: size)
      .clipShape(shape)
      .overlay {
        shape.stroke(Color.white.opacity(0.20), lineWidth: 1)
      }
  }
}

private struct RockYouMarkTile: View {
  let size: CGFloat

  var body: some View {
    let cornerRadius: CGFloat = 6
    ZStack {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(rockYouPurple)
      Text("R")
        .font(.system(size: size * 0.62, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.top, size * 0.02) // optically center the glyph
    }
    .frame(width: size, height: size)
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .stroke(Color.white.opacity(0.25), lineWidth: 1)
    }
  }
}
