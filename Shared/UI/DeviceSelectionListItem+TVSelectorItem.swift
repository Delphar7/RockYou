//
//  DeviceSelectionListItem+TVSelectorItem.swift
//  RockYou (Shared)
//
//  Glue between the cross-platform selection row model and the shared TVSelectorList UI component.
//

import Foundation

extension DeviceSelectionListItem {
  public func toTVSelectorItem() -> TVSelectorItem {
    TVSelectorItem(
      id: id,
      selectionId: selectionId,
      deviceType: deviceType,
      primaryName: primaryName,
      secondaryName: secondaryName,
      linkedDeviceId: capsule?.endpointId,
      linkedDeviceName: capsule?.name,
      linkedDeviceType: capsule?.deviceType
    )
  }
}
