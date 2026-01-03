//
//  Log.swift
//  RockYou Watch Widgets
//
//  Widgets should be quiet and low overhead. This is a widget-only shim so that
//  Shared code can keep calling `Log.*` without dragging the full logger into
//  the widget extension.
//

import Foundation

public enum LogLevel: Int, Comparable {
  case debug = 0
  case info = 1
  case warn = 2
  case error = 3

  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public enum Log {
  public static var minimumLevel: LogLevel = .warn
  public static var noisyEnabled: Bool = false

  @inlinable @inline(__always)
  public static func setLevel(_ level: LogLevel) {}

  @inlinable @inline(__always)
  public static func debug(_ tag: String, _ message: @autoclosure () -> String) {}

  @inlinable @inline(__always)
  public static func noisy(_ tag: String, _ message: @autoclosure () -> String) {}

  @inlinable @inline(__always)
  public static func info(_ tag: String, _ message: @autoclosure () -> String) {}

  @inlinable @inline(__always)
  public static func warn(_ tag: String, _ message: @autoclosure () -> String) {}

  @inlinable @inline(__always)
  public static func error(_ tag: String, _ message: @autoclosure () -> String) {}

  @MainActor
  @inlinable @inline(__always)
  public static func gestureTimeline(
    _ category: String,
    _ event: String,
    _ fields: [String: CustomStringConvertible] = [:]
  ) {}
}
