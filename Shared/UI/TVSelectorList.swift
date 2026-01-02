//
//  TVSelectorList.swift
//  RockYou (Shared)
//
//  Shared TV/device selector list used by iOS dropdown and watchOS sheet.
//

import SwiftUI

// MARK: - Selector Item Model

/// A selectable item in the TV selector list
public struct TVSelectorItem: Identifiable {
  public let id: String           // Unique ID for ForEach
  public let selectionId: String  // ID passed to onSelect (typically the TV's ID)
  public let deviceType: RokuDeviceType
  public let primaryName: String
  public let secondaryName: String?  // Location name (shown underneath on all platforms)
  public let linkedDeviceId: String?    // Paired device id (used for correct power/icon on right)
  public let linkedDeviceName: String?  // Paired device name (shown on right for iOS/macOS)
  public let linkedDeviceType: RokuDeviceType? // Optional device type for the right capsule glyph

  public init(
    id: String,
    selectionId: String,
    deviceType: RokuDeviceType,
    primaryName: String,
    secondaryName: String? = nil,
    linkedDeviceId: String? = nil,
    linkedDeviceName: String? = nil,
    linkedDeviceType: RokuDeviceType? = nil
  ) {
    self.id = id
    self.selectionId = selectionId
    self.deviceType = deviceType
    self.primaryName = primaryName
    self.secondaryName = secondaryName
    self.linkedDeviceId = linkedDeviceId
    self.linkedDeviceName = linkedDeviceName
    self.linkedDeviceType = linkedDeviceType
  }
}

// MARK: - TV Selector List

/// Shared list view for selecting TVs/devices
/// Hosted in platform-specific containers (dropdown overlay on iOS, sheet on watchOS)
public struct TVSelectorList: View {
  let items: [TVSelectorItem]
  let selectedId: String?
  let onSelect: (String) -> Void
  let onRefresh: (() -> Void)?
  let isScanning: Bool

  public init(
    items: [TVSelectorItem],
    selectedId: String?,
    isScanning: Bool = false,
    onSelect: @escaping (String) -> Void,
    onRefresh: (() -> Void)? = nil
  ) {
    self.items = items
    self.selectedId = selectedId
    self.isScanning = isScanning
    self.onSelect = onSelect
    self.onRefresh = onRefresh
  }

  public var body: some View {
    Group {
      if items.isEmpty {
        emptyState
      } else {
        itemsList
      }
    }
  }

  // MARK: - Items List

  private var itemsList: some View {
    TVSelectorListPlatform.itemsList(items: items, selectedId: selectedId, onSelect: onSelect)
  }

  // MARK: - Empty State

  private var emptyState: some View {
    VStack(spacing: 8) {
      Text("No Roku devices found")
        .font(.system(size: TVSelectorListPlatform.emptyStateFontSize))
        .foregroundStyle(.secondary)

      if isScanning {
        ProgressView()
          .scaleEffect(TVSelectorListPlatform.progressScale)
      } else if let refresh = onRefresh {
        Button("Refresh") {
          refresh()
        }
        .font(.system(size: TVSelectorListPlatform.emptyStateFontSize, weight: .medium))
      }
    }
    .padding(.vertical, 16)
  }
}

// MARK: - TV Selector Row

/// Individual row in the selector list
public struct TVSelectorRow: View {
  let item: TVSelectorItem
  let isSelected: Bool
  let onSelect: () -> Void

  public var body: some View {
    Button(action: onSelect) {
      let base =
        Group {
#if os(watchOS)
          if item.linkedDeviceName != nil {
            pairedRowWatchLayout
          } else {
            standardRowLayout
          }
#else
          standardRowLayout
#endif
        }

      TVSelectorListPlatform.rowChrome(base, isSelected: isSelected)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Shared Layout

  private var standardRowLayout: some View {
    HStack(alignment: .center, spacing: iconSpacing) {
      // Device icon (centers naturally against the VStack's total height).
      deviceIcon
        .frame(width: iconSize)
        .offset(x: TVSelectorListPlatform.rowIconXOffset)

      VStack(alignment: .leading, spacing: TVSelectorListPlatform.rowTextLineSpacing) {
        HStack(spacing: 0) {
          // Primary name
          Text(item.primaryName)
            .font(.system(size: primaryFontSize, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.top, 1)

          Spacer(minLength: iconSpacing)
            .overlay(
              Group {
                if item.linkedDeviceName != nil {
                  Rectangle()
                    .fill(.white.opacity(AppOpacity.secondary))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, -iconSpacing * 0.60)  // Extend into the spacing gaps
                }
              },
              alignment: .center
            )
            .offset(y: 1)

          // Linked device name (paired device) - shown in capsule on right
          if let linkedName = item.linkedDeviceName {
            RokuPurpleCapsuleLabel(
              text: linkedName,
              // Show the *paired* device's glyph + power state (not the primary device).
              leadingDeviceType: item.linkedDeviceType ?? .tv,
              leadingPowerMode: linkedPowerMode,
              leadingPadding: 8,
              trailingPadding: 8,
              verticalPadding: 4
            )
            .font(.system(size: secondaryFontSize, weight: .medium))
          }
        }

        // Secondary name (location) - shown underneath on all platforms
        if let location = item.secondaryName {
          Text(location)
            .font(.system(size: secondaryFontSize))
            .foregroundStyle(.white.opacity(AppOpacity.secondary))
            .lineLimit(1)
        }
      }
    }
  }

#if os(watchOS)
  // MARK: - watchOS paired-row layout (3 lines + connector)

  private var pairedRowWatchLayout: some View {
    // Design:
    // 1) TV name
    // 2) TV location
    // 3) Streamer capsule (inset), with an L-shaped connector
    let inset: CGFloat = 12
    let capsuleLeadingPadding: CGFloat = 7
    let capsuleTrailingPadding: CGFloat = 7
    let capsuleVerticalPadding: CGFloat = 1

    return ZStack(alignment: .topLeading) {
      HStack(alignment: .top, spacing: iconSpacing) {
        deviceIcon
          .frame(width: iconSize)
          .offset(x: TVSelectorListPlatform.rowIconXOffset)

        VStack(alignment: .leading, spacing: TVSelectorListPlatform.rowTextLineSpacing) {
          Text(item.primaryName)
            .font(.system(size: primaryFontSize, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.top, 1)

          if let location = item.secondaryName {
            Text(location)
              .font(.system(size: secondaryFontSize))
              .foregroundStyle(.white.opacity(AppOpacity.secondary))
              .lineLimit(1)
          }

          if let linkedName = item.linkedDeviceName {
            HStack(spacing: 0) {
              Spacer().frame(width: inset)
              RokuPurpleCapsuleLabel(
                text: linkedName,
                leadingDeviceType: item.linkedDeviceType ?? .tv,
                leadingPowerMode: linkedPowerMode,
                leadingPadding: capsuleLeadingPadding,
                trailingPadding: capsuleTrailingPadding,
                verticalPadding: capsuleVerticalPadding
              )
              .font(.system(size: secondaryFontSize, weight: .medium))
            }
          }
        }
      }

      // Connector overlay: start at the TV glyph center, end at the capsule glyph center.
      GeometryReader { geo in
        // Horizontal positions are measured from this ZStack's leading edge.
        // - Icon center: ~ iconSize/2 (plus any small platform x offset).
        // - Capsule icon center: iconWidth + spacing + inset + capsuleLeadingPadding + (approx glyph radius)
        let startX = (iconSize * 0.50) + TVSelectorListPlatform.rowIconXOffset
        let startY = (iconSize * 0.50)

        // Connector should stop at the capsule (not run into the glyph).
        // End at the capsule's leading edge with a tiny inset so it visually "touches" the pill.
        let endX =
          iconSize + iconSpacing
          + inset
          + 1

        // Estimate the capsule's vertical center based on text sizing.
        // (We avoid anchor-preference complexity; this is meant to be an “optical” connector.)
        let lineGap = TVSelectorListPlatform.rowTextLineSpacing
        let afterPrimary = 1 + primaryFontSize + lineGap
        let afterSecondary = afterPrimary + (item.secondaryName != nil ? (secondaryFontSize + lineGap) : 0)

        // Capsule is only present for paired rows; if not present, skip drawing.
        if item.linkedDeviceName != nil {
          // Approx capsule height: secondary font + vertical padding top/bot + a little chrome.
          let capsuleH = secondaryFontSize + (capsuleVerticalPadding * 2) + 6
          // Nudge slightly downward so we hit the visual midline of the pill.
          let endY = afterSecondary + (capsuleH * 0.50) + 2

          Path { p in
            p.move(to: CGPoint(x: startX, y: startY))
            p.addLine(to: CGPoint(x: startX, y: endY))
            p.addLine(to: CGPoint(x: endX, y: endY))
          }
          .stroke(.white.opacity(AppOpacity.secondary), lineWidth: 1)
        }
      }
      .allowsHitTesting(false)
    }
  }
#endif

  // MARK: - Device Icon

  /// Get power mode from DeviceStateManager
  private var powerMode: PowerMode {
    // `id` is the primary (left) device id for state/icon.
    DeviceStateManager.shared.state(for: item.id).powerMode
  }

  private var linkedPowerMode: PowerMode {
    guard let id = item.linkedDeviceId else { return .unknown }
    return DeviceStateManager.shared.state(for: id).powerMode
  }

  @ViewBuilder
  private var deviceIcon: some View {
    switch item.deviceType {
    case .tv:
      RokuTVIcon(size: iconSize, screenColor: powerMode.statusColor)
    case .streamingDevice:
      StreamingDeviceIcon(size: iconSize, bodyColor: powerMode.statusColor)
    }
  }

  // MARK: - Platform Sizing

  private let iconSize: CGFloat = TVSelectorListPlatform.rowIconSize
  private let iconSpacing: CGFloat = TVSelectorListPlatform.rowIconSpacing
  private let primaryFontSize: CGFloat = TVSelectorListPlatform.rowPrimaryFontSize
  private let secondaryFontSize: CGFloat = TVSelectorListPlatform.rowSecondaryFontSize
}
