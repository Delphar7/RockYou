//
//  ConfigureTVsView.swift
//  RockYou
//
//  TV configuration panel for pairing TVs with streaming devices.
//

import SwiftUI
import Observation

// MARK: - Configure Devices View (TV-Centric)

@MainActor
@Observable
final class ConfigureTVsState {
  var expandedTVId: String?
  var confirmAction: ConfigureTVsConfirmAction?
  var shareURL: URL?
  var showShareSheet: Bool = false
  var showShareError: String?
  var showCloudKitBlockedAlert: Bool = false

  var discovery: RokuDiscoveryService { RokuDiscoveryService.shared }
  var pairingStore: PairingStore { PairingStore.shared }

  func handleManualRefresh() {
    discovery.refresh()

    let cache = AppCacheManager.shared
    for deviceId in cache.appsByDevice.keys {
      cache.requestForcedIconRefreshAfterNextAppsFetch(for: deviceId, fallbackDelay: 10)
    }
  }

  func createAndShare() async {
    if let blocked = pairingStore.cloudKitBlockedMessage {
      showShareError = blocked
      return
    }
    do {
      shareURL = try await pairingStore.createShareURL()
      showShareSheet = true
    } catch {
      showShareError = error.localizedDescription
    }
  }
}

/// A non-scrolling header row meant to live under the Settings nav bar.
struct ConfigureTVsHeaderRow: View {
  @Bindable var model: ConfigureTVsState

  var body: some View {
    ConfigureTVsSectionHeader(
      isScanning: model.discovery.isScanning,
      isSyncing: model.pairingStore.isSyncing,
      isShared: model.pairingStore.isShared,
      onRefresh: { model.handleManualRefresh() },
      onShare: { Task { await model.createAndShare() } }
    )
    .textCase(nil)
    .background(.ultraThinMaterial)
  }
}

/// The scrollable content (TV list panel) used inside a parent List.
struct ConfigureTVsPanel: View {
  @Bindable var model: ConfigureTVsState

  var body: some View {
    tvListPanel
      .listRowInsets(EdgeInsets())
      .listRowSeparator(.hidden)
  }

  // MARK: - Section Content

  private var tvListPanel: some View {
    VStack(spacing: 6) {
      if model.discovery.tvs.isEmpty && !model.discovery.isScanning {
        emptyState
      }
      ForEach(model.discovery.tvs) { tv in
        TVRow(
          tv: tv,
          mode: .configure,
          pairedStreamer: pairedStreamer(for: tv),
          isExpanded: model.expandedTVId == tv.id,
          streamers: model.discovery.streamingDevices,
          allTVs: model.discovery.tvs,
          pairings: model.pairingStore.asDictionary,
          onExpandToggle: { toggleExpanded(tv) },
          onSelectStreamer: { streamer in
            handleStreamerSelection(tv: tv, streamer: streamer)
          },
          onRemoveStreamerFromCache: { streamer in
            removeStreamerDevice(streamer)
          },
          onRemoveFromCache: {
            removeTVDevice(tv)
          }
        )
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private func removeTVDevice(_ tv: DeviceInfo) {
    // Removing a TV from the discovery cache should not remove other devices.
    // If it has a pairing, unpair first.
    if model.pairingStore.streamerIdForTV(tv.id) != nil {
      model.pairingStore.unpairTV(tv.id)
    }
    model.discovery.removeDeviceFromCache(deviceId: tv.id)
  }

  private func removeStreamerDevice(_ streamer: DeviceInfo) {
    // Removing a streamer from the discovery cache should not remove TVs.
    // If the streamer is currently paired to a TV, unpair first.
    if let tvId = model.pairingStore.tvIdForStreamer(streamer.id) {
      model.pairingStore.unpairTV(tvId)
    }
    model.discovery.removeDeviceFromCache(deviceId: streamer.id)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "tv.slash")
        .font(.system(size: AppFontSize.iconMedium))
        .foregroundStyle(.secondary)
      Text("No Roku TVs found")
        .foregroundStyle(.secondary)
      if !model.discovery.isScanning {
        Button("Refresh") {
          model.handleManualRefresh()
        }
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  // MARK: - Helpers
  private func pairedStreamer(for tv: DeviceInfo) -> DeviceInfo? {
    guard let streamerId = model.pairingStore.streamerIdForTV(tv.id) else { return nil }
    return model.discovery.streamingDevices.first { $0.id == streamerId }
  }

  private func tvForStreamer(_ streamer: DeviceInfo) -> DeviceInfo? {
    guard let tvId = model.pairingStore.tvIdForStreamer(streamer.id) else { return nil }
    return model.discovery.tvs.first { $0.id == tvId }
  }

  private func toggleExpanded(_ tv: DeviceInfo) {
    withAnimation(.easeInOut(duration: 0.2)) {
      model.expandedTVId = (model.expandedTVId == tv.id) ? nil : tv.id
    }
  }

  private func handleStreamerSelection(tv: DeviceInfo, streamer: DeviceInfo?) {
    // Unpair
    guard let streamer = streamer else {
      model.pairingStore.unpairTV(tv.id)
      collapseAndClose()
      return
    }

    // Check if streamer is already bound elsewhere
    if let existingTV = tvForStreamer(streamer), existingTV.id != tv.id {
      let currentlyHasStreamer = model.pairingStore.streamerIdForTV(tv.id) != nil
      model.confirmAction = ConfigureTVsConfirmAction(
        targetTV: tv,
        streamer: streamer,
        existingTV: existingTV,
        canSwap: currentlyHasStreamer
      )
    } else {
      // Simple assignment
      model.pairingStore.pair(
        tvId: tv.id, streamerId: streamer.id, tvName: tv.name, streamerName: streamer.name)
      collapseAndClose()
    }
  }

  private func executeReassign(_ action: ConfigureTVsConfirmAction) {
    // Remove from existing TV, assign to target TV
    model.pairingStore.unpairTV(action.existingTV.id)
    model.pairingStore.pair(
      tvId: action.targetTV.id,
      streamerId: action.streamer.id,
      tvName: action.targetTV.name,
      streamerName: action.streamer.name
    )
    collapseAndClose()
  }

  private func executeSwap(_ action: ConfigureTVsConfirmAction) {
    model.pairingStore.swap(tv1: action.targetTV.id, tv2: action.existingTV.id)
    collapseAndClose()
  }

  private func collapseAndClose() {
    withAnimation(.easeInOut(duration: 0.2)) {
      model.expandedTVId = nil
    }
  }
}

struct ConfigureTVsView: View {
  @State private var model = ConfigureTVsState()

  var body: some View {
    Group {
      Section {
        ConfigureTVsPanel(model: model)
      } header: {
        ConfigureTVsHeaderRow(model: model)
          .textCase(nil)
      }
    }
    .configureTVsDialogs(model: model)
  }
}

extension View {
  /// Shared presentation plumbing for Configure TVs (dialogs/sheets/alerts).
  /// Keeping this centralized avoids duplicating UI state wiring across presentations.
  func configureTVsDialogs(model: ConfigureTVsState) -> some View {
    modifier(ConfigureTVsDialogsModifier(model: model))
  }
}

private struct ConfigureTVsDialogsModifier: ViewModifier {
  @Bindable var model: ConfigureTVsState

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        model.confirmAction?.title ?? "",
        isPresented: .init(
          get: { model.confirmAction != nil },
          set: { if !$0 { model.confirmAction = nil } }
        ),
        titleVisibility: .visible
      ) {
        if let action = model.confirmAction {
          Button("Re-assign") {
            model.pairingStore.unpairTV(action.existingTV.id)
            model.pairingStore.pair(
              tvId: action.targetTV.id,
              streamerId: action.streamer.id,
              tvName: action.targetTV.name,
              streamerName: action.streamer.name
            )
            withAnimation(.easeInOut(duration: 0.2)) { model.expandedTVId = nil }
            model.confirmAction = nil
          }
          if action.canSwap {
            Button("Swap") {
              model.pairingStore.swap(tv1: action.targetTV.id, tv2: action.existingTV.id)
              withAnimation(.easeInOut(duration: 0.2)) { model.expandedTVId = nil }
              model.confirmAction = nil
            }
          }
          Button("Cancel", role: .cancel) { model.confirmAction = nil }
        }
      } message: {
        if let action = model.confirmAction {
          Text(action.message)
        }
      }
      .sheet(isPresented: $model.showShareSheet) {
        if let url = model.shareURL {
          ShareSheet(items: [url])
        }
      }
      .alert(
        "Share Error",
        isPresented: .init(
          get: { model.showShareError != nil },
          set: { if !$0 { model.showShareError = nil } }
        )
      ) {
        Button("OK") { model.showShareError = nil }
      } message: {
        Text(model.showShareError ?? "")
      }
      .alert(
        "iCloud Sync Disabled",
        isPresented: $model.showCloudKitBlockedAlert
      ) {
        Button("OK") { model.showCloudKitBlockedAlert = false }
      } message: {
        Text(model.pairingStore.cloudKitBlockedMessage ?? "")
      }
      .onChange(of: model.pairingStore.cloudKitBlockedMessage) { _, newValue in
        // Important: tie alert presentation to a local state.
        // If we bind isPresented directly to `cloudKitBlockedMessage != nil`,
        // SwiftUI will try to dismiss by setting the binding false, but since the
        // message remains non-nil, the alert immediately re-presents and "OK" looks broken.
        model.showCloudKitBlockedAlert = (newValue != nil)
      }
  }
}

// MARK: - Configure TVs Section Header

private struct ConfigureTVsSectionHeader: View {
  let isScanning: Bool
  let isSyncing: Bool
  let isShared: Bool
  let onRefresh: () -> Void
  let onShare: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      if isScanning || isSyncing {
        ProgressView()
          .scaleEffect(0.8)
      } else {
        Button(action: onRefresh) {
          Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
      }

      Text("Configure TVs")
      Spacer()

      Button(action: onShare) {
        Label("Share", systemImage: isShared ? "person.2.fill" : "square.and.arrow.up")
          .labelStyle(.titleAndIcon)
      }
      .buttonStyle(.borderless)
      .disabled(isSyncing)
    }
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(.primary)
    .padding(.horizontal, 24)
    .padding(.bottom, 12)
  }
}

// MARK: - Confirm Action Model

struct ConfigureTVsConfirmAction {
  let targetTV: DeviceInfo
  let streamer: DeviceInfo
  let existingTV: DeviceInfo
  let canSwap: Bool

  var title: String {
    "\(streamer.name) is paired"
  }

  var message: String {
    "\(streamer.name) is currently paired with \(existingTV.name)."
  }
}

// MARK: - TV Row (Reusable)

struct TVRow: View {
  enum Mode {
    case configure  // Shows chevron, streamer badge, expands to show streamers
    case select  // Simple selection, shows checkmark if selected
  }

  let tv: DeviceInfo
  let mode: Mode

  // Configure mode properties
  var pairedStreamer: DeviceInfo? = nil
  var isExpanded: Bool = false
  var streamers: [DeviceInfo] = []
  var allTVs: [DeviceInfo] = []
  var pairings: [String: String] = [:]
  var onExpandToggle: (() -> Void)? = nil
  var onSelectStreamer: ((DeviceInfo?) -> Void)? = nil
  var onRemoveStreamerFromCache: ((DeviceInfo) -> Void)? = nil
  var onRemoveFromCache: (() -> Void)? = nil

  // Select mode properties
  var isSelected: Bool = false
  var onSelect: (() -> Void)? = nil

  private func powerMode(for device: DeviceInfo) -> PowerMode {
    DeviceStateManager.shared.state(for: device.id).powerMode
  }

  var body: some View {
    VStack(spacing: 0) {
      // Main TV row (tap anywhere to expand/select; icon may have its own sweep gesture)
      HStack(spacing: 12) {
        tvIcon
          .frame(width: 32)

        // TV name
        Text(tv.name)
          .font(
            .system(
              size: AppFontSize.body,
              weight: mode == .select && isSelected ? .semibold : .medium
            )
          )
          .foregroundStyle(.primary)
          .lineLimit(1)

        Spacer()

        // Mode-specific trailing content
        switch mode {
        case .configure:
          streamerBadge
          Image(systemName: "chevron.right")
            .font(.system(size: AppFontSize.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
        case .select:
          if isSelected {
            Image(systemName: "checkmark")
              .font(.system(size: AppFontSize.caption, weight: .semibold))
              .foregroundStyle(rokuPurple)
          }
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(Color.gray.opacity(AppOpacity.light))
      .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
      .contentShape(Rectangle())
      .onTapGesture {
        switch mode {
        case .configure:
          onExpandToggle?()
        case .select:
          onSelect?()
        }
      }

      // Expanded streamer list (configure mode only)
      if mode == .configure && isExpanded {
        streamerList
          .transition(.opacity.combined(with: .move(edge: .top)))
      }
    }
  }

  @ViewBuilder
  private var tvIcon: some View {
    let pm = powerMode(for: tv)
    let base = RokuTVIcon(size: 32, screenColor: pm.statusColor)

      // Only allow "remove from cache" via sweep when the device is clearly off (red state).
      if (pm == .off || pm == .displayOff), let onRemoveFromCache {
        base.sweepable(
          icon: "trash",
          color: .red,
          delay: 1.0,
          tooltip: "Hold to remove from list",
          onQuickTap: {
            // Keep normal behavior consistent: tapping the icon just expands/selects.
            switch mode {
            case .configure:
              onExpandToggle?()
            case .select:
              onSelect?()
            }
          },
          onSweepComplete: {
            onRemoveFromCache()
          }
        )
      } else {
      base
    }
  }

  @ViewBuilder
  private func streamerIcon(_ streamer: DeviceInfo, size: CGFloat, isCurrent: Bool) -> some View {
    let pm = powerMode(for: streamer)
    let base = StreamingDeviceIcon(size: size, bodyColor: pm.statusColor)

      if (pm == .off || pm == .displayOff), let onRemoveStreamerFromCache {
        base.sweepable(
          icon: "trash",
          color: .red,
          delay: 1.0,
          tooltip: "Hold to remove from list",
          onQuickTap: {
            // Preserve existing behavior: quick tap selects the streamer (if not already current).
            if !isCurrent {
              onSelectStreamer?(streamer)
            }
          },
          onSweepComplete: {
            onRemoveStreamerFromCache(streamer)
          }
        )
      } else {
      base
    }
  }

  // MARK: - Streamer Badge (configure mode)
  @ViewBuilder
  private var streamerBadge: some View {
    if let streamer = pairedStreamer {
      RokuPurpleCapsuleLabel(
        text: streamer.name,
        showStreamerPowerIcon: true,
        streamerPowerMode: powerMode(for: streamer),
        leadingPadding: 3,
        trailingPadding: 6,
        verticalPadding: 2
      )
      .font(.system(size: AppFontSize.small, weight: .medium))
      .lineLimit(1)
    } else {
      HStack(spacing: 3) {
        Image(systemName: "circle.dashed")
          .font(.system(size: AppFontSize.small))
        Text("None")
          .font(.system(size: AppFontSize.small, weight: .medium))
      }
      .foregroundStyle(.secondary)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.gray.opacity(AppOpacity.medium))
      .clipShape(Capsule())
    }
  }

  // MARK: - Streamer Selection List (configure mode)
  private var streamerList: some View {
    VStack(spacing: 0) {
      ForEach(streamers) { streamer in
        let boundToTV = tvBoundTo(streamer)
        let isCurrent = pairedStreamer?.id == streamer.id

        Button {
          if !isCurrent {
            onSelectStreamer?(streamer)
          }
        } label: {
          HStack(spacing: 10) {
            streamerIcon(streamer, size: 18, isCurrent: isCurrent)
              .opacity(isCurrent ? 1.0 : 0.6)
              .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
              Text(streamer.name)
                .font(.system(size: AppFontSize.body, weight: isCurrent ? .semibold : .regular))
                .lineLimit(1)
              if let boundTV = boundToTV, boundTV.id != tv.id {
                Text("→ \(boundTV.name)")
                  .font(.system(size: AppFontSize.compact))
                  .foregroundStyle(.orange)
                  .lineLimit(1)
              }
            }

            Spacer()

            if isCurrent {
              Image(systemName: "checkmark")
                .font(.system(size: AppFontSize.caption, weight: .semibold))
                .foregroundStyle(rokuPurple)
            }
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }

      // "None" option to unpair
      if pairedStreamer != nil {
        Divider()
          .padding(.horizontal, 10)

        Button {
          onSelectStreamer?(nil)
        } label: {
          HStack(spacing: 10) {
            Image(systemName: "minus.circle")
              .font(.system(size: AppFontSize.body))
              .foregroundStyle(.secondary)
              .frame(width: 20)
            Text("None")
              .font(.system(size: AppFontSize.body))
              .foregroundStyle(.secondary)
            Spacer()
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 6)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.vertical, 6)
    .background(Color.gray.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .padding(.top, 4)
    .padding(.leading, 44)
  }

  private func tvBoundTo(_ streamer: DeviceInfo) -> DeviceInfo? {
    guard let tvId = pairings.first(where: { $0.value == streamer.id })?.key else { return nil }
    return allTVs.first { $0.id == tvId }
  }
}
