import SwiftUI

enum DPadAssets {
  static func layer(named name: String, size: CGFloat) -> some View {
    // Prefer explicit bundle file lookup so we don't depend on Asset Catalog behavior.
    if let path = Bundle.main.path(forResource: name, ofType: "png"),
      let image = PlatformImage.cachedContentsOfFile(path)
    {
      return AnyView(
        image
          .resizable()
          .scaledToFit()
          .frame(width: size, height: size)
      )
    }

    // Debug fallback: if an image can't be found, show something visible and log.
    DebugBuild.run {
      Log.warn(
        "DPad",
        "Missing DPad image resource: \(name).png (bundle=\(Bundle.main.bundleIdentifier ?? "nil"))"
      )
    }

    return AnyView(
      Circle()
        .fill(Color.red.opacity(0.18))
        .overlay(Circle().stroke(Color.red.opacity(0.9), lineWidth: 1))
        .frame(width: size, height: size)
        .overlay(
          Text("Missing\n\(name)")
            .font(.system(size: max(10, size * 0.09), weight: .semibold))
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
        )
    )
  }
}

/// Small, non-interactive D-Pad glyph composed from the shipped PNG layers.
struct DPadGlyph: View {
  let size: CGFloat

  var body: some View {
    ZStack {
      DPadAssets.layer(named: "DPad-Ring", size: size)

      DPadAssets.layer(named: "StickShadow", size: size)
        .blendMode(.multiply)
        .opacity(0.95)

      DPadAssets.layer(named: "Stick", size: size)
    }
    .frame(width: size, height: size)
  }
}

