// DomePlaygroundView.swift
// RockYou
//
// Unified playground for dome-related algorithms and experiments.
// Uses a button bar with sub-menus for algorithm categories.
// macOS-only (excluded from iOS via build settings)

import SwiftUI

// MARK: - Algorithm Selection

enum DomePlaygroundCategory: String, CaseIterable {
  case iris2D = "Iris 2D"
  case flower = "Flower"
  case shatter = "Shatter"
}

enum Iris2DAlgorithm: String, CaseIterable {
  case kinematics = "Kinematics"
  case sectorDirect = "Sector Direct"
}

enum ShatterAlgorithm: String, CaseIterable {
  case shatter = "Shatter"  // Unified explode/confetti (mode picker inside)
  case ripple = "Ripple"
  case irisDebug = "Iris Debug"
  case iris = "Iris"
}

// MARK: - Playground View

struct DomePlaygroundView: View {
  private static let selectionKey = "DomePlaygroundSelection"

  @State private var selectedCategory: DomePlaygroundCategory = .iris2D
  @State private var selectedIris2D: Iris2DAlgorithm = .kinematics
  @State private var selectedShatter: ShatterAlgorithm = .shatter

  init() {
    // Load saved selection
    if let dict = UserDefaults.standard.dictionary(forKey: Self.selectionKey) {
      if let catRaw = dict["category"] as? String,
         let cat = DomePlaygroundCategory(rawValue: catRaw) {
        _selectedCategory = State(initialValue: cat)
      }
      if let iris2DRaw = dict["iris2D"] as? String,
         let iris2D = Iris2DAlgorithm(rawValue: iris2DRaw) {
        _selectedIris2D = State(initialValue: iris2D)
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
      "iris2D": selectedIris2D.rawValue,
      "shatter": selectedShatter.rawValue,
    ]
    UserDefaults.standard.set(dict, forKey: Self.selectionKey)
  }

  var body: some View {
    VStack(spacing: 0) {
      // Category selector header
      HStack(spacing: 12) {
        ForEach(DomePlaygroundCategory.allCases, id: \.self) { category in
          if category == .iris2D {
            // Iris 2D has a sub-menu
            Menu {
              ForEach(Iris2DAlgorithm.allCases, id: \.self) { algo in
                Button(algo.rawValue) {
                  selectedCategory = .iris2D
                  selectedIris2D = algo
                }
              }
            } label: {
              categoryButton(category)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
          } else if category == .shatter {
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

        // Show which sub-algorithm is selected
        if selectedCategory == .iris2D {
          Text(selectedIris2D.rawValue)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(4)
        } else if selectedCategory == .shatter {
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
    .onChange(of: selectedIris2D) { _, _ in saveSelection() }
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
    case .iris2D:
      switch selectedIris2D {
      case .kinematics:
        IrisKinematicsConfigurableView()
      case .sectorDirect:
        IrisSectorDirectDebugView()
      }

    case .flower:
      BloomingFlowerDebugView()

    case .shatter:
      switch selectedShatter {
      case .shatter:
        ShatterDebugView()
      case .ripple:
        RippleDebugView()
      case .irisDebug:
        IrisDebugView()
      case .iris:
        IrisProductionDebugView()
      }
    }
  }
}

#Preview("Dome Playground") {
  DomePlaygroundView()
    .frame(width: 950, height: 700)
}
