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
  @Binding var isPresentingHelp: Bool
  let barBounds: Anchor<CGRect>

  private static let helpMaterialSeed: UInt64 = 0xC0FFEE

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

            // Bottom row: Configure (primary) + Help (aux).
            HStack(spacing: 10) {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)

              Button {
                // Keep the dropdown visible while presenting Help so the presentation
                // isn't cancelled by removing this view from the hierarchy.
                isPresentingHelp = true
              } label: {
                Image(systemName: "questionmark")
                  .font(.system(size: AppFontSize.medium, weight: .semibold))
                  .foregroundStyle(.white)
                  // Visually a capsule (not a big circle), but keep a solid tap target.
                  .frame(width: 54, height: 28)
              }
              .buttonStyle(
                MaterialButtonEffect.CapsuleStyle(
                  baseColor: rokuPurple, seed: Self.helpMaterialSeed)
              )
              .frame(minWidth: 44, minHeight: 42)
              .contentShape(Rectangle())
              // Nudge the whole capsule up slightly (material effect reads bottom-heavy otherwise).
              .offset(y: -1.5)
              .accessibilityLabel("Help")
            }
            .padding(.horizontal, 12)
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
    let controllers = DeviceControllerBuilder.buildControllers(
      discovered: discovery.discoveredDevices,
      pairings: pairingStore.pairings
    )

    // Preserve a similar grouping to the old UI:
    // - TVs
    // - Paired controllers
    // - Streamers
    let ordered = controllers.sorted { a, b in
      func rank(_ c: DeviceControllerDescriptor) -> Int {
        switch c.kind {
        case .tv: return 0
        case .paired: return 1
        case .streamer: return 2
        }
      }
      let ra = rank(a), rb = rank(b)
      if ra != rb { return ra < rb }
      let la = (a.location ?? "").localizedCaseInsensitiveCompare(b.location ?? "")
      if la != .orderedSame { return la == .orderedAscending }
      let na = a.displayName.localizedCaseInsensitiveCompare(b.displayName)
      if na != .orderedSame { return na == .orderedAscending }
      return a.id < b.id
    }

    let devicesById = Dictionary(uniqueKeysWithValues: discovery.discoveredDevices.map { ($0.id, $0) })

    return ordered.map { controller in
      DeviceSelectionListItemBuilder
        .build(
          controller: controller,
          devicesById: devicesById,
          selectionIdPolicy: .tvIdForPairedElseControllerId
        )
        .toTVSelectorItem()
    }
  }
}
