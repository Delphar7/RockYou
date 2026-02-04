// FullScreenDomeView.swift
// RockYou/UI/Dome
//
// Dome layer that renders behind the remote controls UI.
// Inserted in RemoteControlView.shellContent() behind the controls
// GeometryReader. Clips to the controls area (left pane on split view).

import SwiftUI

struct FullScreenDomeView: View {
  @ObservedObject private var manager = DomeAnimationManager.shared

  var body: some View {
    if manager.isActive {
      GeometryReader { geo in
        let viewportCenterY = geo.frame(in: .global).midY
        let offsetY = manager.dpadGlobalCenterY - viewportCenterY
        DomeDoorsView(
          openProgress: max(0, manager.openProgress),
          viewportSize: geo.size,
          referenceDomeSize: manager.referenceDomeSize,
          onComplete: { manager.reportComplete() }
        )
        .offset(y: offsetY)
      }
      .allowsHitTesting(false)
    }
  }
}

/// Full-screen tap overlay placed ON TOP of controls in the ZStack.
/// Catches any click/tap during the dome animation to surface the DPad.
/// Removes itself once the DPad is surfaced, restoring normal interaction.
struct DomeTapThroughOverlay: View {
  @ObservedObject private var manager = DomeAnimationManager.shared

  var body: some View {
    if manager.isActive && !manager.dpadSurfaced {
      Color.clear
        .contentShape(Rectangle())
        .onTapGesture {
          manager.dpadSurfaced = true
        }
    }
  }
}
