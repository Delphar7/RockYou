import SwiftUI

  extension View {
    func platformRemoteSurface(isActive: Bool) -> some View {
      self
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
              isActive
                ? rokuPurple.opacity(AppOpacity.mediumLight)
                : Color.gray.opacity(AppOpacity.verySubtle),
              lineWidth: 8
            )
            .blur(radius: 2)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
              isActive
                ? rokuPurple.opacity(AppOpacity.semiOpaque)
                : Color.gray.opacity(AppOpacity.subtle),
              lineWidth: 4
            )
        )
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(
              isActive ? rokuPurple.opacity(AppOpacity.primary) : Color.gray.opacity(AppOpacity.light),
              lineWidth: 1.5
            )
        )
        .animation(.easeInOut(duration: 0.15), value: isActive)
    }
  }
