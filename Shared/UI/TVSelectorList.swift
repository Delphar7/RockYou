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
  public let linkedDeviceName: String?  // Paired device name (shown on right for iOS/macOS)

  public init(
    id: String,
    selectionId: String,
    deviceType: RokuDeviceType,
    primaryName: String,
    secondaryName: String? = nil,
    linkedDeviceName: String? = nil
  ) {
    self.id = id
    self.selectionId = selectionId
    self.deviceType = deviceType
    self.primaryName = primaryName
    self.secondaryName = secondaryName
    self.linkedDeviceName = linkedDeviceName
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
        VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: iconSpacing) {
          // Device icon
          deviceIcon
            .frame(width: iconSize)

          // Primary name
          Text(item.primaryName)
            .font(.system(size: primaryFontSize, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(.white)
            .lineLimit(1)

          Spacer()
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
            ).offset(y: 1)

          // Linked device name (paired device) - shown in capsule on right
          if let linkedName = item.linkedDeviceName {
            RokuPurpleCapsuleLabel(
              text: linkedName,
              showStreamerPowerIcon: item.deviceType == .streamingDevice,
              streamerPowerMode: powerMode,
              leadingPadding: 8,
              trailingPadding: 8,
              verticalPadding: 4
            )
            .font(.system(size: secondaryFontSize, weight: .medium))
          }

          // Checkmark
          if isSelected {
            Image(systemName: "checkmark")
              .font(.system(size: checkmarkSize, weight: .semibold))
              .foregroundStyle(Color.white.opacity(AppOpacity.secondary))
          }
        }

        // Secondary name (location) - shown underneath on all platforms
        if let location = item.secondaryName {
          HStack(spacing: iconSpacing) {
            Spacer().frame(width: iconSize + iconSpacing)
            Text(location)
              .font(.system(size: secondaryFontSize))
              .foregroundStyle(.white.opacity(AppOpacity.secondary))
              .lineLimit(1)
            Spacer()
          }
        }
      }

      TVSelectorListPlatform.rowChrome(base)
    }
    .buttonStyle(.plain)
  }

  // MARK: - Device Icon

  /// Get power mode from DeviceStateManager
  private var powerMode: PowerMode {
    DeviceStateManager.shared.state(for: item.id).powerMode
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
  private let checkmarkSize: CGFloat = TVSelectorListPlatform.rowCheckmarkSize
}
