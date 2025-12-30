import SwiftUI

/// Roku-branded icons used across the app and in the watch widget/complication.
///
/// Kept free of dependencies on `Shared/UI/*` so it can compile inside the WidgetKit extension
/// without pulling in unrelated UI code.
public struct RokuTVIcon: View {
  public var size: CGFloat
  public var screenColor: Color

  public init(size: CGFloat = 28, screenColor: Color = .clear) {
    self.size = size
    self.screenColor = screenColor
  }

  public var body: some View {
    ZStack {
      // TV frame outline
      RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
        .fill(Color.gray.opacity(0.30))
        .frame(width: size, height: size * 0.72)

      // Screen area (optionally colored)
      RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
        .fill(screenColor)
        .frame(width: size * 0.85, height: size * 0.58)

      // Roku "R" glyph
      Text("R")
        .font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
        .foregroundStyle(Color.white)

      // TV stand
      VStack(spacing: 0) {
        Spacer()
        RoundedRectangle(cornerRadius: 1)
          .fill(Color.gray.opacity(0.40))
          .frame(width: size * 0.5, height: size * 0.06)
          .offset(y: size * 0.02)
      }
      .frame(width: size, height: size * 0.8)
    }
    .frame(width: size, height: size * 0.8)
  }
}

public struct StreamingDeviceIcon: View {
  public var size: CGFloat
  public var bodyColor: Color

  public init(size: CGFloat = 20, bodyColor: Color = .clear) {
    self.size = size
    self.bodyColor = bodyColor
  }

  public var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        .fill(bodyColor)
        .frame(width: size, height: size * 0.55)

      Text("R")
        .font(.system(size: size * 0.45, weight: .heavy, design: .rounded))
        .foregroundStyle(Color.white)
    }
    .frame(width: size, height: size * 0.55)
  }
}
