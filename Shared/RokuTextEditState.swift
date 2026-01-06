//
//  RokuTextEditState.swift
//  RockYou (Shared)
//
//  Shared model + manager for Roku ECP-2 text edit ("keyboard") state.
//

import Foundation
import Observation

public struct RokuTextEditState: Sendable, Equatable {
  public var texteditId: String
  public var text: String?
  public var masked: String?
  public var maxLength: String?
  public var selectionStart: String?
  public var selectionEnd: String?
  public var textEditType: String?

  public init(
    texteditId: String,
    text: String? = nil,
    masked: String? = nil,
    maxLength: String? = nil,
    selectionStart: String? = nil,
    selectionEnd: String? = nil,
    textEditType: String? = nil
  ) {
    self.texteditId = texteditId
    self.text = text
    self.masked = masked
    self.maxLength = maxLength
    self.selectionStart = selectionStart
    self.selectionEnd = selectionEnd
    self.textEditType = textEditType
  }
}

public enum RokuTextEditStatus: Sendable, Equatable {
  case editing(RokuTextEditState)
  case off

  public var isActive: Bool {
    switch self {
    case .editing: return true
    case .off: return false
    }
  }

  /// Returns nil when Roku reports `none` / empty.
  public var texteditId: String? {
    switch self {
    case .off:
      return nil
    case .editing(let state):
      let id = state.texteditId
      if id.isEmpty || id == "none" { return nil }
      return id
    }
  }

  /// Last-known remote text (if provided by notifications or fetched by query).
  /// Note: this may be nil if the device hasn't provided text yet.
  public var text: String? {
    switch self {
    case .off: return nil
    case .editing(let state): return state.text
    }
  }

  /// Convenience for UI: remote text if known, otherwise empty string.
  public var textOrEmpty: String {
    text ?? ""
  }
}

/// Live textedit status keyed by device id (selected device can change).
@Observable
@MainActor
public final class RokuTextEditStateManager {
  public static let shared = RokuTextEditStateManager()

  public private(set) var statuses: [String: RokuTextEditStatus] = [:]

  /// Optional async hook to fetch a full textedit snapshot when notifications are partial.
  /// Installed by the app layer (iOS/macOS) since Shared shouldn't know about networking.
  @ObservationIgnored
  private var snapshotFetcher: (@Sendable (_ deviceId: String) async -> RokuTextEditState?)? = nil

  // Debounced snapshot tasks keyed by device id.
  @ObservationIgnored
  private var snapshotTasks: [String: Task<Void, Never>] = [:]
  @ObservationIgnored
  private var lastSnapshotAttemptAt: [String: Date] = [:]

  private init() {}

  /// Install a snapshot fetcher once (idempotent).
  public func installSnapshotFetcherIfNeeded(
    _ fetcher: @escaping @Sendable (_ deviceId: String) async -> RokuTextEditState?
  ) {
    if snapshotFetcher == nil {
      snapshotFetcher = fetcher
    }
  }

  public func status(for deviceId: String?) -> RokuTextEditStatus {
    guard let deviceId else { return .off }
    return statuses[deviceId] ?? .off
  }

  public func setStatus(_ status: RokuTextEditStatus, for deviceId: String) {
    statuses[deviceId] = status
  }

  public func updateFromState(_ state: RokuTextEditState?, for deviceId: String) {
    guard let state else {
      setStatus(.off, for: deviceId)
      return
    }

    if state.texteditId.isEmpty || state.texteditId == "none" {
      setStatus(.off, for: deviceId)
      cancelSnapshotTask(for: deviceId)
      return
    }

    // Merge partial updates: some notifications may omit `text` (or other fields).
    if case .editing(let existing) = statuses[deviceId],
       existing.texteditId == state.texteditId
    {
      let merged = RokuTextEditState(
        texteditId: state.texteditId,
        text: state.text ?? existing.text,
        masked: state.masked ?? existing.masked,
        maxLength: state.maxLength ?? existing.maxLength,
        selectionStart: state.selectionStart ?? existing.selectionStart,
        selectionEnd: state.selectionEnd ?? existing.selectionEnd,
        textEditType: state.textEditType ?? existing.textEditType
      )
      setStatus(.editing(merged), for: deviceId)
    } else {
      setStatus(.editing(state), for: deviceId)
    }
  }

  /// High-level entrypoint for websocket notifications.
  /// If the update does not include `text`, we will debounce a snapshot fetch to keep the UI
  /// in sync with external editors (e.g. the official Roku app).
  public func noteRemoteUpdate(_ state: RokuTextEditState?, for deviceId: String) {
    updateFromState(state, for: deviceId)

    guard let state else {
      cancelSnapshotTask(for: deviceId)
      return
    }

    // If we already have text (or there's no fetcher), we're done.
    guard state.text == nil else { return }
    guard snapshotFetcher != nil else { return }

    scheduleSnapshotFetchDebounced(for: deviceId, expectedTexteditId: state.texteditId)
  }

  private func scheduleSnapshotFetchDebounced(for deviceId: String, expectedTexteditId: String) {
    cancelSnapshotTask(for: deviceId)

    let task = Task { [weak self] in
      // Debounce: allow a burst of notifications to settle.
      try? await Task.sleep(nanoseconds: 200_000_000)  // 200ms
      guard !Task.isCancelled else { return }
      await self?.fetchSnapshotIfStillNeeded(for: deviceId, expectedTexteditId: expectedTexteditId)
    }
    snapshotTasks[deviceId] = task
  }

  private func cancelSnapshotTask(for deviceId: String) {
    snapshotTasks[deviceId]?.cancel()
    snapshotTasks[deviceId] = nil
  }

  private func fetchSnapshotIfStillNeeded(for deviceId: String, expectedTexteditId: String) async {
    guard let fetcher = snapshotFetcher else { return }

    // Rate-limit snapshot attempts per device (avoid spinning if firmware never provides text).
    let now = Date()
    if let last = lastSnapshotAttemptAt[deviceId], now.timeIntervalSince(last) < 1.0 {
      return
    }
    lastSnapshotAttemptAt[deviceId] = now

    // Only fetch if we're still on the same active field and still missing text.
    guard case .editing(let existing) = statuses[deviceId] else { return }
    guard existing.texteditId == expectedTexteditId else { return }
    if existing.text != nil { return }

    guard let snapshot = await fetcher(deviceId) else { return }
    // Apply snapshot (do not re-trigger fetch from this apply).
    updateFromState(snapshot, for: deviceId)
  }

  public func clear(for deviceId: String) {
    statuses[deviceId] = .off
    cancelSnapshotTask(for: deviceId)
  }
}
