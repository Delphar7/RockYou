// ConfigurableEngine.swift
// RockYou (Shared)
//
// Protocol for engines with configurable properties.
// Engines conforming to this can be used:
//   1. In Debug panes with auto-generated UI (EngineConfigPanel)
//   2. In production with direct property access: engine.radius = 0.5
//
// The same engine file works in both contexts - just move it from
// Debug/Playground/ to RockYou/UI/ when ready for production.

import Foundation

// MARK: - Property Descriptor

/// Describes a configurable property for UI generation
public struct PropertyDescriptor: Sendable {
  public let name: String
  public let control: ControlHint

  public init(_ name: String, _ control: ControlHint = .auto) {
    self.name = name
    self.control = control
  }

  /// Hints for what UI control to generate
  public enum ControlHint: Sendable {
    case auto  // Infer from property type
    case slider(min: Double, max: Double, step: Double = 0.01)
    case toggle
    case intStepper(min: Int, max: Int, step: Int = 1)
    case picker([String])
    case color
    case text
  }
}

// MARK: - Configurable Engine Protocol

/// Protocol for engines that expose configurable properties.
///
/// Conforming types declare their configurable properties via `propertyDescriptors`.
/// Debug UI uses this to auto-generate controls. Production code ignores it.
///
/// Example:
/// ```swift
/// @Observable
/// final class MyEngine: ConfigurableEngine {
///     var radius: Double = 0.5
///     var segments: Int = 12
///     var enabled: Bool = true
///
///     static let propertyDescriptors: [String: PropertyDescriptor] = [
///         "radius": .init("Radius", .slider(min: 0, max: 2)),
///         "segments": .init("Segments", .intStepper(min: 4, max: 64)),
///         "enabled": .init("Enabled", .toggle),
///     ]
///
///     // Required: get/set by string key for dynamic UI binding
///     func getValue(forKey key: String) -> Any? { ... }
///     func setValue(_ value: Any, forKey key: String) { ... }
/// }
/// ```
public protocol ConfigurableEngine: AnyObject {
  /// Property descriptors keyed by property name (must match actual property names)
  static var propertyDescriptors: [String: PropertyDescriptor] { get }

  /// Dynamic getter for UI binding
  func getValue(forKey key: String) -> Any?

  /// Dynamic setter for UI binding
  func setValue(_ value: Any, forKey key: String)
}

// MARK: - Type-Safe Accessor Helpers

/// Helper to reduce boilerplate in getValue/setValue implementations.
/// Usage in your engine:
/// ```swift
/// func getValue(forKey key: String) -> Any? {
///     switch key {
///     case "radius": return radius
///     case "segments": return segments
///     default: return nil
///     }
/// }
/// ```
///
/// Or use the macro-based approach (future enhancement).

public extension ConfigurableEngine {
  /// Ordered list of property keys for consistent UI ordering
  static var propertyKeys: [String] {
    // Sort alphabetically by display name for consistent ordering
    propertyDescriptors.sorted { $0.value.name < $1.value.name }.map(\.key)
  }
}
