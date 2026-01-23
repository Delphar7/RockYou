// DomePlaygroundView.swift
// RockYou
//
// Unified playground for dome-related algorithms and experiments.
// Uses a dropdown to switch between different algorithm views.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

// MARK: - Algorithm Selection

enum DomePlaygroundAlgorithm: String, CaseIterable, Identifiable {
  case sampleGeometry = "Sample Geometry"
  case bloomingFlower = "Blooming Flower"
  case particleExplosion = "Particle Explosion"

  var id: String { rawValue }

  var description: String {
    switch self {
    case .sampleGeometry:
      return "ConfigurableEngine pattern demo"
    case .bloomingFlower:
      return "Iris blade aperture animation"
    case .particleExplosion:
      return "GPU-driven fragment shatter"
    }
  }
}

// MARK: - Playground View

struct DomePlaygroundView: View {
  @State private var selectedAlgorithm: DomePlaygroundAlgorithm = .sampleGeometry

  var body: some View {
    VStack(spacing: 0) {
      // Algorithm selector header
      HStack {
        Text("Algorithm:")
          .foregroundStyle(.secondary)

        Picker("", selection: $selectedAlgorithm) {
          ForEach(DomePlaygroundAlgorithm.allCases) { algorithm in
            Text(algorithm.rawValue).tag(algorithm)
          }
        }
        .labelsHidden()
        .frame(width: 180)

        Text(selectedAlgorithm.description)
          .font(.caption)
          .foregroundStyle(.tertiary)

        Spacer()
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
      .background(Color(NSColor.windowBackgroundColor))

      Divider()

      // Selected algorithm view
      algorithmView
    }
  }

  @ViewBuilder
  private var algorithmView: some View {
    switch selectedAlgorithm {
    case .sampleGeometry:
      SampleGeometryDebugView()

    case .bloomingFlower:
      BloomingFlowerDebugView()

    case .particleExplosion:
      ParticleExplosionDebugView()
    }
  }
}

#Preview("Dome Playground") {
  DomePlaygroundView()
    .frame(width: 950, height: 700)
}
