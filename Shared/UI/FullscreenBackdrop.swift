//
//  FullscreenBackdrop.swift
//  RockYou
//
//  Reusable fullscreen backdrop for overlays.
//  Catches taps to prevent interaction with underlying views.
//

import SwiftUI

struct FullscreenBackdrop<Content: View>: View {
  let opacity: CGFloat
  let material: Material
  let onTap: () -> Void
  @ViewBuilder let content: (CGSize) -> Content

  init(
    opacity: CGFloat = 0.7,
    material: Material = .ultraThinMaterial,
    onTap: @escaping () -> Void,
    @ViewBuilder content: @escaping (CGSize) -> Content
  ) {
    self.opacity = opacity
    self.material = material
    self.onTap = onTap
    self.content = content
  }

  var body: some View {
    GeometryReader { geo in
      ZStack {
        Color.black.opacity(opacity)
          .background(material)
          .contentShape(Rectangle())
          // Absorb drags so underlying ScrollViews don't scroll, and treat a no-move drag as a tap to cancel.
          .gesture(
            DragGesture(minimumDistance: 0)
              .onEnded { value in
                if abs(value.translation.width) < 6, abs(value.translation.height) < 6 {
                  onTap()
                }
              }
          )

        content(geo.size)
      }
    }
    .ignoresSafeArea()
    .transition(.opacity)
  }
}
