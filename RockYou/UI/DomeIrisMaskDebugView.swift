// DomeIrisMaskDebugView.swift
// RockYou
//
// Debug view for validating the 2D iris mask symmetry.

import CoreGraphics
import SwiftUI

struct DomeIrisMaskDebugView: View {
  @State private var t: Double = 0
  @State private var bladeCount: Double = 8
  @State private var maskImage: CGImage?

  private let config = DomeIrisConfig.default
  private let imageSize = 512

  var body: some View {
    VStack(spacing: 16) {
      ZStack {
        Color.black.opacity(0.9)
        if let maskImage {
          Image(decorative: maskImage, scale: 1)
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .padding(12)
        } else {
          ProgressView()
        }
      }
      .frame(width: 320, height: 320)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

      VStack(alignment: .leading, spacing: 8) {
        LabeledContent("t") {
          Text("\(t, specifier: "%.2f")")
            .frame(width: 64, alignment: .trailing)
        }
        Slider(value: $t, in: 0...1)

        LabeledContent("N") {
          Text("\(Int(bladeCount))")
            .frame(width: 64, alignment: .trailing)
        }
        Slider(value: $bladeCount, in: 3...16, step: 1)
      }
    }
    .padding(20)
    .onAppear(perform: refreshImage)
    .onChange(of: t) { _, _ in refreshImage() }
    .onChange(of: bladeCount) { _, _ in refreshImage() }
  }

  private func refreshImage() {
    let n = max(3, Int(bladeCount.rounded()))
    let tt = Float(t)
    let tUnlock = DomeIrisAnimation.tUnlock(tt, unlockEnd: config.unlockEnd)
    maskImage = DomeIrisMaskRenderer.makeMaskImage(
      size: imageSize,
      t: tUnlock,
      bladeCount: n,
      config: config,
      flipY: false
    )
  }
}

#if DEBUG
  #Preview("Dome Iris Mask Debug") {
    DomeIrisMaskDebugView()
  }
#endif
