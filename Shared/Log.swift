//
//  Log.swift
//  RockYou (Shared)
//
//  Unified logging for Phone and Watch.
//  Thread-safe, callable from any context.
//

import Foundation

/// Log levels for filtering output
public enum LogLevel: Int, Comparable {
  case debug = 0
  case info = 1
  case warn = 2
  case error = 3

  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  var prefix: String {
    switch self {
    case .debug: return "🔍"
    case .info: return "ℹ️"
    case .warn: return "⚠️"
    case .error: return "❌"
    }
  }
}

/// Unified logger - thread-safe, works from any context
public enum Log {

  /// Minimum level to output (set to .warn for release builds if desired)
  public static var minimumLevel: LogLevel = DebugBuild.isEnabled ? .info : .warn

  /// Extra-noisy packet-level logging. This is intentionally opt-in and should
  /// only be enabled by editing this value in code.
  public static var noisyEnabled: Bool = true

  // MARK: - Public API

  /// Set the minimum log level at runtime
  public static func setLevel(_ level: LogLevel) {
    minimumLevel = level
  }

  /// Debug-level logging (verbose, development only)
  public static func debug(_ tag: String, _ message: String) {
    log(.debug, tag, message)
  }

  /// Extra-noisy logging (full packet dumps, etc.). Not governed by minimumLevel.
  public static func noisy(_ tag: String, _ message: String) {
    guard noisyEnabled else { return }
    write("[\(tag)] 🗯️ \(message)")
  }

  /// Info-level logging (normal operations)
  public static func info(_ tag: String, _ message: String) {
    log(.info, tag, message)
  }

  /// Warning-level logging (unexpected but recoverable)
  public static func warn(_ tag: String, _ message: String) {
    log(.warn, tag, message)
  }

  /// Error-level logging (failures)
  public static func error(_ tag: String, _ message: String) {
    log(.error, tag, message)
  }

  // MARK: - Gesture timeline (debug-only)

  /// Debug-only event timeline logger for gesture-sensitive code paths.
  /// In release builds this compiles to near-no-ops.
  @MainActor
  public static func gestureTimeline(
    _ category: String,
    _ event: String,
    _ fields: [String: CustomStringConvertible] = [:]
  ) {
    guard DebugBuild.isEnabled else { return }
    guard GestureTimeline.enabled else { return }
    let ts = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
    if fields.isEmpty {
      Log.debug("GestureTL", "[t+\(ts)] \(category):\(event)")
      return
    }

    // Stable field ordering helps diff logs between runs.
    let payload =
      fields
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value.description)" }
      .joined(separator: " ")

    Log.debug("GestureTL", "[t+\(ts)] \(category):\(event) \(payload)")
  }

  // MARK: - Private

  private static func log(_ level: LogLevel, _ tag: String, _ message: String) {
    guard level >= minimumLevel else { return }

    let logMessage = "[\(tag)] \(level.prefix) \(message)"
    write(logMessage)
  }

  private static func write(_ message: String) {
    // Write to stderr (good for piping to `mac.log`).
    let ts = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
    let stamped = "[t+\(ts)] \(message)"
    if let data = (stamped + "\n").data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }
}

// MARK: - Gesture timeline config

@MainActor
public enum GestureTimeline {
  /// Runtime toggle for debug sessions. (In release builds this is always false.)
  @MainActor private static var enabledInDebug: Bool = true

  public static var enabled: Bool {
    get { DebugBuild.isEnabled ? enabledInDebug : false }
    set {
      guard DebugBuild.isEnabled else { return }
      enabledInDebug = newValue
    }
  }
}
