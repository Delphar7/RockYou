//
//  TVSelectorDropdown.swift
//  RockYou
//
//  TV/device selector dropdown and bar components (iOS/macOS).
//  Uses shared TVSelectorList for the actual list content.
//

import SwiftUI

// MARK: - TV Selector Bar

struct TVSelectorBarBoundsKey: PreferenceKey {
  static var defaultValue: Anchor<CGRect>?

  static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
    value = value ?? nextValue()
  }
}

struct TVSelectorBar: View {
  let selectedTVName: String?
  let selectedStreamerName: String?  // Non-nil if TV has a paired streamer
  let selectedDeviceId: String?
  let showingSelector: Bool
  let onTap: () -> Void

  private let dotSize: CGFloat = 8
  private let dotSpacing: CGFloat = 6

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 1) {
        // TV name above (only when streamer is paired)
        if selectedStreamerName != nil, let tvName = selectedTVName {
          Text(tvName)
            .font(.system(size: AppFontSize.compact))
            .foregroundStyle(.white.opacity(AppOpacity.twoThirds))
            .padding(.leading, dotSize + dotSpacing)
        }

        // Main row: dot, primary name, chevron
        HStack(spacing: dotSpacing) {
          if let name = selectedStreamerName ?? selectedTVName {
            ConnectionStatusDot(deviceId: selectedDeviceId)
            Text(name)
              .font(.system(size: AppFontSize.medium, weight: .medium))
          } else {
            Text("Select TV...")
              .font(.system(size: AppFontSize.medium, weight: .medium))
          }
          Image(systemName: "chevron.down")
            .font(.system(size: AppFontSize.caption, weight: .semibold))
            .rotationEffect(.degrees(showingSelector ? 180 : 0))
        }
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
    }
    .buttonStyle(.plain)
    .anchorPreference(key: TVSelectorBarBoundsKey.self, value: .bounds) { $0 }
  }
}

// MARK: - TV Selector Dropdown

struct TVSelectorDropdown: View {
  @Binding var isShowing: Bool
  @Binding var isPresentingConfigure: Bool
  let barBounds: Anchor<CGRect>

  private var pairingStore: PairingStore { PairingStore.shared }
  private var discovery: RokuDiscoveryService { RokuDiscoveryService.shared }

  var body: some View {
    GeometryReader { proxy in
      let barRect = proxy[barBounds]
      let gapBelowBar: CGFloat = 8
      let horizontalInset: CGFloat = 16
      let dropdownWidth = min(proxy.size.width - (horizontalInset * 2), 420)

      let minCenterX = horizontalInset + dropdownWidth / 2
      let maxCenterX = proxy.size.width - horizontalInset - dropdownWidth / 2
      let targetCenterX = min(max(barRect.midX, minCenterX), maxCenterX)
      let xOffset = targetCenterX - proxy.size.width / 2

      ZStack(alignment: .top) {
        // Full-screen tap blocker
        Color.black.opacity(AppOpacity.moderate)
          .ignoresSafeArea()
          .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
              isShowing = false
            }
          }

        // Dropdown content
        VStack(spacing: 0) {
          Spacer()
            .frame(height: barRect.maxY + gapBelowBar)

          VStack(spacing: 0) {
            TVSelectorList(
              items: selectorItems,
              selectedId: pairingStore.currentSelection?.id ?? pairingStore.currentTVId,
              isScanning: discovery.isScanning,
              onSelect: { selectionId in
                if discovery.tvs.contains(where: { $0.id == selectionId }) {
                  pairingStore.selectTV(selectionId)
                } else if discovery.streamingDevices.contains(where: { $0.id == selectionId }) {
                  pairingStore.select(.streamer(id: selectionId))
                } else {
                  pairingStore.select(nil)
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                  isShowing = false
                }
              },
              onRefresh: { discovery.refresh() }
            )

            Divider()
              .background(Color.white.opacity(AppOpacity.light))

            Button {
              withAnimation(.easeInOut(duration: 0.2)) {
                isShowing = false
              }
              // Present Settings (which contains ConfigureTVsView).
              isPresentingConfigure = true
            } label: {
              HStack(spacing: 10) {
                Image(systemName: "gearshape.fill")
                  .font(.system(size: AppFontSize.body, weight: .semibold))
                  .foregroundStyle(.white.opacity(AppOpacity.twoThirds))
                Text("Configure Roku/TV Pairs…")
                  .font(.system(size: AppFontSize.body, weight: .medium))
                  .foregroundStyle(.white)
                Spacer()
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 10)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          .frame(width: dropdownWidth)
          .background(Color(white: 0.15))
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .shadow(color: .black.opacity(AppOpacity.semiOpaque), radius: 12, x: 0, y: 6)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .offset(x: xOffset)
      }
    }
    .transition(.opacity)
    .zIndex(100)
  }

  // MARK: - Build Selector Items

  private func secondaryLabel(location: String?, kind: String) -> String? {
    if let location, !location.isEmpty { return "\(location) • \(kind)" }
    return kind
  }

  /// Build the list of items for TVSelectorList
  private var selectorItems: [TVSelectorItem] {
    var items: [TVSelectorItem] = []

    // Unpaired TVs (control via built-in Roku)
    for tv in unpairedTVs {
      items.append(TVSelectorItem(
        id: tv.id,
        selectionId: tv.id,
        deviceType: .tv,
        primaryName: tv.name,
        secondaryName: secondaryLabel(location: tv.location, kind: "TV"),
        linkedDeviceName: nil
      ))
    }

    // Paired streamers (with location underneath and TV name on right)
    for streamer in pairedStreamers {
      if let pairedTV = pairedTVForStreamer(streamer) {
        items.append(TVSelectorItem(
          id: streamer.id,
          selectionId: pairedTV.id,  // Selecting streamer actually selects the TV
          deviceType: .streamingDevice,
          primaryName: streamer.name,
          secondaryName: secondaryLabel(location: streamer.location, kind: "Streamer"),
          linkedDeviceName: pairedTV.name
        ))
      }
    }

    // Unpaired streamers (show as top-level selectable device)
    for streamer in unpairedStreamers {
      items.append(TVSelectorItem(
        id: streamer.id,
        selectionId: streamer.id,
        deviceType: .streamingDevice,
        primaryName: streamer.name,
        secondaryName: secondaryLabel(location: streamer.location, kind: "Streamer"),
        linkedDeviceName: nil
      ))
    }

    return items
  }

  /// TVs without a paired streaming device (controlled via built-in Roku)
  private var unpairedTVs: [DeviceInfo] {
    let pairedTVIds = Set(pairingStore.pairings.map { $0.tvId })
    return discovery.tvs.filter { !pairedTVIds.contains($0.id) }
  }

  /// Streaming devices that are paired to a TV
  private var pairedStreamers: [DeviceInfo] {
    discovery.streamingDevices.filter { pairingStore.tvIdForStreamer($0.id) != nil }
  }

  /// Streaming devices not paired to any TV
  private var unpairedStreamers: [DeviceInfo] {
    discovery.streamingDevices.filter { pairingStore.tvIdForStreamer($0.id) == nil }
  }

  /// Get the TV paired with a streamer
  private func pairedTVForStreamer(_ streamer: DeviceInfo) -> DeviceInfo? {
    guard let tvId = pairingStore.tvIdForStreamer(streamer.id) else { return nil }
    return discovery.tvs.first { $0.id == tvId }
  }
}
