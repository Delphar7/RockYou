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
        DomeDoorsView(
          openProgress: min(1, max(0, manager.openProgress)),
          viewportSize: geo.size,
          referenceDomeSize: manager.referenceDomeSize,
          onComplete: { manager.reportComplete() }
        )
      }
      .allowsHitTesting(false)
    }
  }
}
