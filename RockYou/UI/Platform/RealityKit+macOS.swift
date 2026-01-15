//
//  RealityKit+macOS.swift
//  RockYou
//
//  macOS-specific RealityKit helpers.
//

import AppKit
import CoreGraphics
import RealityKit

// MARK: - ARView Snapshot Setup

/// Configures an `ARView` for offscreen snapshot rendering.
/// macOS `ARView` does not expose iOS-only APIs like `cameraMode` / `renderOptions`.
@MainActor
func prepareARViewForSnapshot(_ view: ARView) {
  let _ = view
}

/// Attaches an `ARView` off-screen so `ARView.snapshot()` can render reliably.
/// Returns true if successful.
@MainActor
func attachOffscreenARViewToWindow(_ view: ARView, size: CGSize) -> Bool {
  guard size.width > 0, size.height > 0 else { return false }
  guard let window = NSApplication.shared.windows.first else { return false }

  view.frame = CGRect(x: -size.width * 2, y: -size.height * 2, width: size.width, height: size.height)
  window.contentView?.addSubview(view)
  return true
}

// MARK: - Lock Overlay

/// Handles tap on the lock overlay. iOS shows a tooltip, macOS unlocks directly.
@MainActor
func handleLockOverlayTap(globalFrame: CGRect, dpadSize: CGFloat, unlock: @escaping () -> Void) {
  let _ = globalFrame
  let _ = dpadSize
  unlock()
}
