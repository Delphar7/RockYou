//
//  RealityKit+iOS.swift
//  RockYou
//
//  iOS-specific RealityKit helpers.
//

import CoreGraphics
import RealityKit
import UIKit

// MARK: - ARView Snapshot Setup

/// Configures an `ARView` for offscreen snapshot rendering.
@MainActor
func prepareARViewForSnapshot(_ view: ARView) {
  view.cameraMode = .nonAR
  view.renderOptions = [.disableMotionBlur, .disableDepthOfField]
}

/// Attaches an `ARView` off-screen so `ARView.snapshot()` can render reliably.
/// Returns true if successful.
@MainActor
func attachOffscreenARViewToWindow(_ view: ARView, size: CGSize) -> Bool {
  guard size.width > 0, size.height > 0 else { return false }
  guard
    let window = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first?.windows.first
  else {
    return false
  }

  view.frame = CGRect(
    x: -size.width * 2, y: -size.height * 2, width: size.width, height: size.height)
  window.addSubview(view)
  return true
}

// MARK: - Lock Overlay

/// Handles tap on the lock overlay. iOS shows a tooltip, macOS unlocks directly.
@MainActor
func handleLockOverlayTap(globalFrame: CGRect, dpadSize: CGFloat, unlock: @escaping () -> Void) {
  let _ = unlock
  TooltipManager.shared.show(
    "Swipe up to unlock",
    buttonFrame: .init(
      x: globalFrame.midX - dpadSize / 2,
      y: globalFrame.midY - dpadSize * 0.525,
      width: dpadSize,
      height: dpadSize * 1.05
    )
  )
}
