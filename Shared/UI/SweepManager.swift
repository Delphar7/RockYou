//
//  SweepManager.swift
//  RockYou (Shared)
//
//  Shared state for fullscreen sweep overlay.
//  Used by .sweepable() modifier for hold-to-confirm buttons.
//  Replaces PowerSweepManager with generalized icon/color support.
//

import SwiftUI
import Combine

enum SweepOverlayIcon {
  case systemName(String)
  case view(AnyView)
}

@MainActor
final class SweepManager: ObservableObject {
  static let shared = SweepManager()

  @Published private(set) var isShowing = false
  @Published private(set) var progress: CGFloat = 0
  @Published private(set) var icon: SweepOverlayIcon = .systemName("power")
  @Published private(set) var color: Color = .red

  var onCancel: (() -> Void)?
  private var dismissTask: Task<Void, Never>?

  func show(icon: SweepOverlayIcon, color: Color) {
    dismissTask?.cancel()
    dismissTask = nil
    self.icon = icon
    self.color = color
    self.progress = 0
    withAnimation(.easeOut(duration: 0.12)) {
      self.isShowing = true
    }
  }

  func show(iconSystemName: String, color: Color) {
    show(icon: .systemName(iconSystemName), color: color)
  }

  func dismiss(immediately: Bool = false) {
    dismissTask?.cancel()
    dismissTask = nil

    if immediately {
      isShowing = false
      progress = 0
      return
    }

    withAnimation(.easeOut(duration: 0.12)) {
      isShowing = false
    }
    // Reset progress after the fade completes to avoid visual "jump" if the overlay is reinserted.
    dismissTask = Task {
      try? await Task.sleep(nanoseconds: 150_000_000)
      guard !Task.isCancelled else { return }
      self.progress = 0
      self.dismissTask = nil
    }
  }

  func dismiss(after seconds: TimeInterval) {
    let clamped = max(0, seconds)
    if clamped == 0 {
      dismiss()
      return
    }

    dismissTask?.cancel()
    dismissTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(clamped * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self.dismiss()
    }
  }

  func updateProgress(_ value: CGFloat) {
    progress = value
  }
}

// MARK: - Sweep Overlay View

struct SweepOverlayView: View {
  @ObservedObject var manager = SweepManager.shared

  var body: some View {
    if manager.isShowing {
      FullscreenBackdrop(opacity: 0.7, material: .ultraThinMaterial, onTap: { manager.onCancel?() })
      { size in
        sweepIndicator(surfaceSize: size)
      }
    }
  }

  private func sweepIndicator(surfaceSize: CGSize) -> some View {
    let diameter = 0.5 * min(surfaceSize.width, surfaceSize.height)
    let ringLineWidth = max(6, diameter * 0.08)
    let systemIconSize = max(22, diameter * 0.42)
    let appIconWidth = max(44, diameter * 0.72)
    let appIconHeight = appIconWidth * (3.0 / 4.0)
    let appIconCornerRadius = max(10, diameter * 0.14)

    return ZStack {
      // Background circle - uses dynamic color
      Circle()
        .stroke(manager.color.opacity(AppOpacity.standard), lineWidth: ringLineWidth)
        .frame(width: diameter, height: diameter)

      // Sweep progress (clock-hand style from top)
      Circle()
        .trim(from: 0, to: manager.progress)
        .stroke(
          manager.progress < 1 ? Color.white : Color.green,
          style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
        )
        .frame(width: diameter, height: diameter)
        .rotationEffect(.degrees(-90))

      // Dynamic icon - transitions from color to white as sweep progresses
      switch manager.icon {
      case .systemName(let name):
        Image(systemName: name)
          .font(.system(size: systemIconSize, weight: .medium))
          .foregroundStyle(iconColor)
      case .view(let view):
        view
          .frame(width: appIconWidth, height: appIconHeight)
          .clipShape(RoundedRectangle(cornerRadius: appIconCornerRadius, style: .continuous))
      }
    }
  }

  // Interpolate from manager.color -> white as progress increases
  private var iconColor: Color {
    let c = manager.color.components
    let p = manager.progress
    return Color(
      red: c.red * (1 - p) + p,
      green: c.green * (1 - p) + p,
      blue: c.blue * (1 - p) + p
    )
  }
}

// MARK: - Color Extension for RGB components

extension Color {
  var components: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    rgbaComponentsOrZero
  }
}
