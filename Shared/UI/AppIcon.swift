import SwiftUI

/// Minimal app-icon tile renderer.
///
/// Responsibilities:
/// - Render a provided `Image?` (or a caller-supplied placeholder view when nil)
/// - Apply an explicit treatment (e.g. input centering slide)
/// - Clip to a rounded-rect
/// - Draw a default border
///
/// Non-responsibilities:
/// - Labels (outside/embedded)
/// - AppStrip-only "active glow" chrome
struct AppIcon<Placeholder: View>: View {
  let image: Image?
  let size: CGSize
  let cornerRadius: CGFloat
  var treatment: AppIconTreatment = .normalFill

  /// Whether to draw the default border.
  var showsBorder: Bool = true
  var borderColor: Color = Color.gray.opacity(AppOpacity.primary)
  var borderWidth: CGFloat = 1

  @ViewBuilder let placeholder: () -> Placeholder

  @Environment(\.displayScale) private var displayScale

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    ZStack {
      if let image {
        treatedImage(image: image)
      } else {
        placeholder()
      }
    }
    .frame(width: size.width, height: size.height)
    .clipShape(shape)
    .overlay {
      if showsBorder {
        shape.stroke(borderColor, lineWidth: borderWidth)
      }
    }
  }

  @ViewBuilder
  private func treatedImage(image: Image) -> some View {
    switch treatment {
    case .normalFill:
      image
        .resizable()
        .aspectRatio(contentMode: .fill)

    case .normalFit:
      image
        .resizable()
        .aspectRatio(contentMode: .fit)

    case .inputTopFit:
      VStack(spacing: 0) {
        image
          .resizable()
          .aspectRatio(contentMode: .fit)
        Spacer(minLength: 0)
      }

    case let .inputCenterByPanel(slideFraction, topTrimOffsetY, topTrimHeight, topTrimInsetX):
      GeometryReader { geo in
        let snapToPixel: (CGFloat) -> CGFloat = { value in
          let s = max(1, displayScale)
          return (value * s).rounded() / s
        }

        // Key detail: trimming must happen *before* the slide, otherwise we're just clipping empty space.
        // Also snap to pixels to avoid subpixel edge filtering artifacts.
        // Slide is expressed as a fraction of the icon tile height so it scales with any frame size/aspect.
        let slide = snapToPixel(geo.size.height * slideFraction)
        let trimOffsetY = snapToPixel(topTrimOffsetY)
        let trimHeight = snapToPixel(topTrimHeight)
        let trimInsetX = snapToPixel(topTrimInsetX)

        image
          .resizable()
          // This treatment is intended for 4×3-ish icon tiles (e.g. AppStrip, NowPlaying).
          // Using `.fit` avoids unwanted horizontal cropping; slide/trim handles the panel centering.
          .aspectRatio(contentMode: .fit)
          .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
          // Punch out the top border strip (center-only, inset from rounded corners).
          .mask {
            ZStack(alignment: .top) {
              Rectangle().fill(Color.white)
              Rectangle()
                .fill(Color.black)
                .frame(
                  width: max(0, geo.size.width - (2 * trimInsetX)),
                  height: max(0, trimHeight)
                )
                .offset(y: trimOffsetY)
                .blendMode(.destinationOut)
            }
            .compositingGroup()
          }
          // Now slide the already-trimmed icon down for panel-centering.
          .offset(y: slide)
          .clipped()
      }
    }
  }

  // MARK: - Utilities
}

/// Non-generic helper namespace for app icon classification / shared logic.
enum AppIconClassifier {
  static func isInput(appId: String, appType: String?) -> Bool {
    appId.hasPrefix("tvinput.") || (appType == "tvin")
  }
}

/// Explicit image treatment / alignment policy for `AppIcon`.
///
/// Kept non-generic so it can be referenced without needing to bind `AppIcon<Placeholder>`.
enum AppIconTreatment: Sendable {
  case normalFill
  case normalFit
  case inputTopFit
  case inputCenterByPanel(
    slideFraction: CGFloat = 0.11,
    topTrimOffsetY: CGFloat = 0,
    topTrimHeight: CGFloat = 1,
    topTrimInsetX: CGFloat = 1
  )
}
