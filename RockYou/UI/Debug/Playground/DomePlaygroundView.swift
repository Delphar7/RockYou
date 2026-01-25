// DomePlaygroundView.swift
// RockYou
//
// Unified playground for dome-related algorithms and experiments.
// Uses a button bar with sub-menus for algorithm categories.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

// MARK: - Algorithm Selection

enum DomePlaygroundCategory: String, CaseIterable {
  case sample = "Sample"
  case flower = "Flower"
  case shatter = "Shatter"
}

enum ShatterAlgorithm: String, CaseIterable {
  case explode = "Explode"
  case confetti = "Confetti"
  case ripple = "Ripple"
}

// MARK: - Playground View

struct DomePlaygroundView: View {
  private static let selectionKey = "DomePlaygroundSelection"

  @State private var selectedCategory: DomePlaygroundCategory = .sample
  @State private var selectedShatter: ShatterAlgorithm = .explode

  init() {
    // Load saved selection
    if let dict = UserDefaults.standard.dictionary(forKey: Self.selectionKey) {
      if let catRaw = dict["category"] as? String,
         let cat = DomePlaygroundCategory(rawValue: catRaw) {
        _selectedCategory = State(initialValue: cat)
      }
      if let shatterRaw = dict["shatter"] as? String,
         let shatter = ShatterAlgorithm(rawValue: shatterRaw) {
        _selectedShatter = State(initialValue: shatter)
      }
    }
  }

  private func saveSelection() {
    let dict: [String: String] = [
      "category": selectedCategory.rawValue,
      "shatter": selectedShatter.rawValue,
    ]
    UserDefaults.standard.set(dict, forKey: Self.selectionKey)
  }

  var body: some View {
    VStack(spacing: 0) {
      // Category selector header
      HStack(spacing: 12) {
        ForEach(DomePlaygroundCategory.allCases, id: \.self) { category in
          if category == .shatter {
            // Shatter has a sub-menu
            Menu {
              ForEach(ShatterAlgorithm.allCases, id: \.self) { algo in
                Button(algo.rawValue) {
                  selectedCategory = .shatter
                  selectedShatter = algo
                }
              }
            } label: {
              categoryButton(category)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
          } else {
            Button {
              selectedCategory = category
            } label: {
              categoryButton(category)
            }
            .buttonStyle(.plain)
          }
        }

        Spacer()

        // Show which shatter algorithm is selected
        if selectedCategory == .shatter {
          Text(selectedShatter.rawValue)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(4)
        }
      }
      .padding(.horizontal)
      .padding(.vertical, 8)
      .background(Color(NSColor.windowBackgroundColor))

      Divider()

      // Selected view
      selectedView
    }
    .onChange(of: selectedCategory) { _, _ in saveSelection() }
    .onChange(of: selectedShatter) { _, _ in saveSelection() }
  }

  @ViewBuilder
  private func categoryButton(_ category: DomePlaygroundCategory) -> some View {
    Text(category.rawValue)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(selectedCategory == category ? Color.accentColor : Color.clear)
      .foregroundStyle(selectedCategory == category ? .white : .primary)
      .cornerRadius(6)
  }

  @ViewBuilder
  private var selectedView: some View {
    switch selectedCategory {
    case .sample:
      SampleGeometryDebugView()

    case .flower:
      BloomingFlowerDebugView()

    case .shatter:
      switch selectedShatter {
      case .explode:
        ExplodeDebugView()
      case .confetti:
        ConfettiDebugView()
      case .ripple:
        RippleDebugView()
      }
    }
  }
}

#Preview("Dome Playground") {
  DomePlaygroundView()
    .frame(width: 950, height: 700)
}
