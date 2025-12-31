//
//  RemoteButton.swift
//  RockYou
//
//  Reusable remote control button with consistent styling.
//  Platform-adaptive: shadows on iOS/Mac, swipe-aware on Watch.
//

import SwiftUI

// MARK: - Button Style

enum RemoteButtonStyle {
  // Watch styles (smaller, flexible width)
  /// Compact rectangular: 30pt height, no label (Watch NavPage, MediaPage)
  case rect
  /// Labeled rectangular: 48pt height, with text label (Watch QuickActionsPage)
  case rectLabeled
  /// Circular: 40x40 (Watch MediaPage circles)
  case circle

  // iOS/Mac styles (fixed sizes, larger)
  /// iOS top key: 54x44 rectangular
  case iosRect
  /// iOS circle key: 64x64 circular
  case iosCircle(size: CGFloat = 64)

  /// Custom size
  case custom(width: CGFloat?, height: CGFloat, isCircle: Bool, iconSize: CGFloat? = nil, cornerRadius: CGFloat? = nil)

  var height: CGFloat {
    switch self {
    case .rect: return 30
    case .rectLabeled: return 48
    case .circle: return 40
    case .iosRect: return 44
    case .iosCircle(let size): return size
    case .custom(_, let h, _, _, _): return h
    }
  }

  var width: CGFloat? {
    switch self {
    case .rect, .rectLabeled: return nil  // maxWidth: .infinity
    case .circle: return 40
    case .iosRect: return 54
    case .iosCircle(let size): return size
    case .custom(let w, _, _, _, _): return w
    }
  }

  var isCircle: Bool {
    switch self {
    case .circle, .iosCircle: return true
    case .custom(_, _, let c, _, _): return c
    default: return false
    }
  }

  var showLabel: Bool {
    switch self {
    case .rectLabeled: return true
    default: return false
    }
  }

  var iconSize: CGFloat {
    switch self {
    case .rect: return 14
    case .rectLabeled: return 18
    case .circle: return 16
    case .iosRect: return 22
    case .iosCircle(let size): return size * 0.35
    case .custom(_, _, _, let size, _): return (size ?? 11.5) * 1.3
    }
  }

  var cornerRadius: CGFloat {
    switch self {
    case .rect: return 8
    case .rectLabeled: return 10
    case .iosRect: return 12
    case .custom(_, _, _, _, let r): return r ?? 8
    default: return 8
    }
  }
}

// MARK: - Remote Button

struct RemoteButton: View {
  let icon: String
  let action: () -> Void
  var label: String? = nil
  var style: RemoteButtonStyle = .rect
  var baseColor: Color? = nil

  private var materialSeed: UInt64 {
    // Stable per-button seed so the texture crop doesn't jump between renders.
    // Include style so the same icon used in a different family doesn't accidentally match.
    let tag = style.isCircle ? "circle" : "rect"
    let colorTag = (baseColor == nil) ? "default" : "custom"
    return "\(icon)|\(label ?? "")|\(tag)|\(colorTag)".stableHash64
  }

  var body: some View {
    RemoteButtonPlatform.makeBody(
      action: action,
      content: AnyView(content),
      style: style,
      baseColor: baseColor,
      materialSeed: materialSeed
    )
  }

  private var content: some View {
    let base =
      Group {
      if style.showLabel, let label = label {
        VStack(spacing: 2) {
          Image(systemName: icon)
            .font(.system(size: style.iconSize, weight: .semibold))
          Text(label)
            .font(.system(size: AppFontSize.small, weight: .medium))
        }
      } else {
        Image(systemName: icon)
          .font(.system(size: style.iconSize, weight: .semibold))
      }
    }
    .foregroundStyle(.white)
    .frame(width: style.width, height: style.height)
    .frame(maxWidth: style.width == nil ? .infinity : nil)

    return RemoteButtonPlatform.decorateContent(
      base: base,
      style: style,
      baseColor: baseColor,
      buttonShape: AnyShape(buttonShape)
    )
  }

  private var buttonShape: some Shape {
    style.isCircle
      ? AnyShape(Circle())
      : AnyShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
  }
}

// MARK: - Convenience Initializers

extension RemoteButton {
  /// Quick init for icon-only rectangular button
  init(_ icon: String, action: @escaping () -> Void) {
    self.icon = icon
    self.action = action
    self.style = RemoteButtonPlatform.defaultIconOnlyRectStyle
  }

  /// Quick init for labeled rectangular button (Watch)
  init(_ icon: String, label: String, action: @escaping () -> Void) {
    self.icon = icon
    self.label = label
    self.style = .rectLabeled
    self.action = action
  }

  /// Quick init for circular button with size (iOS)
  init(_ icon: String, circleSize: CGFloat, action: @escaping () -> Void) {
    self.icon = icon
    self.style = .iosCircle(size: circleSize)
    self.action = action
  }
}
