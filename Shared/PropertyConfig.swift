// PropertyConfig.swift
// RockYou (Shared)
//
// KeyPath-based property configuration for auto-generated UI.
// Declare properties normally, then list them in a config array.
//
// Usage:
// ```swift
// @Observable
// final class MyEngine {
//   var speed: Double = 1.0
//   var enabled: Bool = true
//   var mode: Mode = .normal
//
//   static let config: [PropertyConfig<MyEngine>] = [
//     .slider(\.speed, "Speed", 0...10, step: 0.1),
//     .toggle(\.enabled, "Enabled"),
//     .picker(\.mode, "Mode"),
//   ]
// }
// ```

import Foundation
import SwiftUI

// MARK: - Property Config

/// Type-erased property configuration for UI generation
public struct PropertyConfig<Engine: AnyObject> {
  public let name: String
  public let control: Control
  let getValue: (Engine) -> Any
  let setValue: (Engine, Any) -> Void

  public enum Control {
    case slider(min: Double, max: Double, step: Double)
    case toggle
    case stepper(min: Int, max: Int, step: Int)
    case picker(options: [String], fromIndex: (Int) -> Any, toIndex: (Any) -> Int)
    case text
    case color
  }
}

// MARK: - Slider (Double, Float, CGFloat)

public extension PropertyConfig {
  /// Slider for Double values
  static func slider(
    _ keyPath: ReferenceWritableKeyPath<Engine, Double>,
    _ name: String,
    _ range: ClosedRange<Double>,
    step: Double = 0.01
  ) -> PropertyConfig {
    PropertyConfig(
      name: name,
      control: .slider(min: range.lowerBound, max: range.upperBound, step: step),
      getValue: { $0[keyPath: keyPath] },
      setValue: { engine, value in
        if let v = value as? Double { engine[keyPath: keyPath] = v }
      }
    )
  }

  /// Slider for Float values
  static func slider(
    _ keyPath: ReferenceWritableKeyPath<Engine, Float>,
    _ name: String,
    _ range: ClosedRange<Double>,
    step: Double = 0.01
  ) -> PropertyConfig {
    PropertyConfig(
      name: name,
      control: .slider(min: range.lowerBound, max: range.upperBound, step: step),
      getValue: { Double($0[keyPath: keyPath]) },
      setValue: { engine, value in
        if let v = value as? Double { engine[keyPath: keyPath] = Float(v) }
      }
    )
  }

  /// Slider for CGFloat values
  static func slider(
    _ keyPath: ReferenceWritableKeyPath<Engine, CGFloat>,
    _ name: String,
    _ range: ClosedRange<Double>,
    step: Double = 0.01
  ) -> PropertyConfig {
    PropertyConfig(
      name: name,
      control: .slider(min: range.lowerBound, max: range.upperBound, step: step),
      getValue: { Double($0[keyPath: keyPath]) },
      setValue: { engine, value in
        if let v = value as? Double { engine[keyPath: keyPath] = CGFloat(v) }
      }
    )
  }
}

// MARK: - Toggle (Bool)

public extension PropertyConfig {
  /// Toggle for Bool values
  static func toggle(
    _ keyPath: ReferenceWritableKeyPath<Engine, Bool>,
    _ name: String
  ) -> PropertyConfig {
    PropertyConfig(
      name: name,
      control: .toggle,
      getValue: { $0[keyPath: keyPath] },
      setValue: { engine, value in
        if let v = value as? Bool { engine[keyPath: keyPath] = v }
      }
    )
  }
}

// MARK: - Stepper (Int)

public extension PropertyConfig {
  /// Stepper for Int values
  static func stepper(
    _ keyPath: ReferenceWritableKeyPath<Engine, Int>,
    _ name: String,
    _ range: ClosedRange<Int>,
    step: Int = 1
  ) -> PropertyConfig {
    PropertyConfig(
      name: name,
      control: .stepper(min: range.lowerBound, max: range.upperBound, step: step),
      getValue: { $0[keyPath: keyPath] },
      setValue: { engine, value in
        if let v = value as? Int { engine[keyPath: keyPath] = v }
      }
    )
  }
}

// MARK: - Picker (CaseIterable enums)

public extension PropertyConfig {
  /// Picker for any CaseIterable enum
  /// Uses String(describing:) for display, or rawValue if RawRepresentable<String>
  static func picker<V: CaseIterable & Hashable>(
    _ keyPath: ReferenceWritableKeyPath<Engine, V>,
    _ name: String
  ) -> PropertyConfig where V.AllCases: RandomAccessCollection {
    let allCases = Array(V.allCases)
    let options = allCases.map { displayName(for: $0) }

    return PropertyConfig(
      name: name,
      control: .picker(
        options: options,
        fromIndex: { allCases[$0] },
        toIndex: { value in
          guard let v = value as? V else { return 0 }
          return allCases.firstIndex(of: v).map { allCases.distance(from: allCases.startIndex, to: $0) } ?? 0
        }
      ),
      getValue: { $0[keyPath: keyPath] },
      setValue: { engine, value in
        if let v = value as? V { engine[keyPath: keyPath] = v }
      }
    )
  }

  /// Get display name for enum case
  private static func displayName<V>(for value: V) -> String {
    // Try RawRepresentable<String> first for custom display names
    if let raw = value as? any RawRepresentable,
       let stringRaw = raw.rawValue as? String {
      return stringRaw
    }
    // Fall back to case name with capitalization
    let desc = String(describing: value)
    return desc.prefix(1).uppercased() + desc.dropFirst()
  }
}

// MARK: - Text (String)

public extension PropertyConfig {
  /// Text field for String values
  static func text(
    _ keyPath: ReferenceWritableKeyPath<Engine, String>,
    _ name: String
  ) -> PropertyConfig {
    PropertyConfig(
      name: name,
      control: .text,
      getValue: { $0[keyPath: keyPath] },
      setValue: { engine, value in
        if let v = value as? String { engine[keyPath: keyPath] = v }
      }
    )
  }
}

// MARK: - Int Field (for large integers like fragment count)

public extension PropertyConfig {
  /// Text field for Int values (useful for large numbers that don't fit a stepper)
  static func intField(
    _ keyPath: ReferenceWritableKeyPath<Engine, Int>,
    _ name: String
  ) -> PropertyConfig {
    PropertyConfig(
      name: name,
      control: .text,
      getValue: { $0[keyPath: keyPath] },
      setValue: { engine, value in
        if let v = value as? Int {
          engine[keyPath: keyPath] = v
        } else if let s = value as? String, let v = Int(s) {
          engine[keyPath: keyPath] = v
        }
      }
    )
  }
}

// MARK: - Color

public extension PropertyConfig {
  /// Color picker
  static func color(
    _ keyPath: ReferenceWritableKeyPath<Engine, Color>,
    _ name: String
  ) -> PropertyConfig {
    PropertyConfig(
      name: name,
      control: .color,
      getValue: { $0[keyPath: keyPath] },
      setValue: { engine, value in
        if let v = value as? Color { engine[keyPath: keyPath] = v }
      }
    )
  }
}

// MARK: - UserDefaults Persistence

public extension PropertyConfig {
  /// Save all config values to UserDefaults
  static func save<E: AnyObject>(_ engine: E, config: [PropertyConfig<E>], key: String) {
    var dict: [String: Any] = [:]
    for prop in config {
      let value = prop.getValue(engine)
      // Only save types that UserDefaults supports
      switch value {
      case let v as Double: dict[prop.name] = v
      case let v as Float: dict[prop.name] = Double(v)
      case let v as CGFloat: dict[prop.name] = Double(v)
      case let v as Int: dict[prop.name] = v
      case let v as Bool: dict[prop.name] = v
      case let v as String: dict[prop.name] = v
      default: break  // Skip unsupported types (Color, enums, etc.)
      }
    }
    UserDefaults.standard.set(dict, forKey: key)
  }

  /// Load config values from UserDefaults
  static func load<E: AnyObject>(_ engine: E, config: [PropertyConfig<E>], key: String) {
    guard let dict = UserDefaults.standard.dictionary(forKey: key) else { return }
    for prop in config {
      if let value = dict[prop.name] {
        prop.setValue(engine, value)
      }
    }
  }

  /// Clear saved config from UserDefaults
  static func clear(key: String) {
    UserDefaults.standard.removeObject(forKey: key)
  }
}
