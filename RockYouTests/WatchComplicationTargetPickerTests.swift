import XCTest
@testable import RockYou

@MainActor
final class WatchComplicationTargetPickerTests: XCTestCase {

  func testPick_prefersSingleOnWithActiveApp() {
    let devices: [DeviceInfo] = [
      .init(id: "A", name: "Living", ipAddress: "1.1.1.1", isTV: true),
      .init(id: "B", name: "Bedroom", ipAddress: "1.1.1.2", isTV: true),
    ]
    var sA = DeviceState()
    sA.powerMode = .on
    sA.activeApp = "netflix"
    var sB = DeviceState()
    sB.powerMode = .on
    sB.activeApp = nil

    let snapshot = WatchSurfaceSnapshot(
      generatedAt: 123,
      devices: devices,
      deviceStates: ["A": sA, "B": sB]
    )

    let picked = WatchComplicationTargetPicker.pick(snapshot: snapshot, lastActiveDeviceId: "B")
    XCTAssertEqual(picked?.deviceId, "A")
    XCTAssertEqual(picked?.priority, .singleOnWithActiveApp)
  }

  func testPick_fallsBackToSingleOn() {
    let devices: [DeviceInfo] = [
      .init(id: "A", name: "Living", ipAddress: "1.1.1.1", isTV: true),
      .init(id: "B", name: "Bedroom", ipAddress: "1.1.1.2", isTV: true),
    ]
    var sA = DeviceState()
    sA.powerMode = .off
    var sB = DeviceState()
    sB.powerMode = .on

    let snapshot = WatchSurfaceSnapshot(
      generatedAt: 123,
      devices: devices,
      deviceStates: ["A": sA, "B": sB]
    )

    let picked = WatchComplicationTargetPicker.pick(snapshot: snapshot, lastActiveDeviceId: "A")
    XCTAssertEqual(picked?.deviceId, "B")
    XCTAssertEqual(picked?.priority, .singleOn)
  }

  func testPick_usesLastActiveWhenNoSingleWinners() {
    let devices: [DeviceInfo] = [
      .init(id: "A", name: "Living", ipAddress: "1.1.1.1", isTV: true),
      .init(id: "B", name: "Bedroom", ipAddress: "1.1.1.2", isTV: true),
    ]
    var sA = DeviceState()
    sA.powerMode = .on
    var sB = DeviceState()
    sB.powerMode = .on

    let snapshot = WatchSurfaceSnapshot(
      generatedAt: 123,
      devices: devices,
      deviceStates: ["A": sA, "B": sB]
    )

    let picked = WatchComplicationTargetPicker.pick(snapshot: snapshot, lastActiveDeviceId: "B")
    XCTAssertEqual(picked?.deviceId, "B")
    XCTAssertEqual(picked?.priority, .lastActive)
  }

  func testPick_usesFirstDeviceWhenNoLastActive() {
    let devices: [DeviceInfo] = [
      .init(id: "A", name: "Living", ipAddress: "1.1.1.1", isTV: true),
      .init(id: "B", name: "Bedroom", ipAddress: "1.1.1.2", isTV: true),
    ]

    let snapshot = WatchSurfaceSnapshot(generatedAt: 123, devices: devices, deviceStates: [:])
    let picked = WatchComplicationTargetPicker.pick(snapshot: snapshot, lastActiveDeviceId: nil)
    XCTAssertEqual(picked?.deviceId, "A")
    XCTAssertEqual(picked?.priority, .firstAvailable)
  }
}
