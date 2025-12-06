import XCTest
@testable import RockYou

final class SweepableTouchTargetPickerTests: XCTestCase {
  func testPickIndex_ignoresSuppressedCandidates() {
    let point = CGPoint(x: 10, y: 10)
    let candidates: [SweepableTouchTargetPicker.Candidate] = [
      .init(frame: CGRect(x: 0, y: 0, width: 100, height: 100), isSuppressed: true, debugLabel: "suppressed"),
      .init(frame: CGRect(x: 0, y: 0, width: 100, height: 100), isSuppressed: false, debugLabel: "active"),
    ]
    XCTAssertEqual(SweepableTouchTargetPicker.pickIndex(at: point, candidates: candidates), 1)
  }

  func testPickIndex_returnsNilWhenNoHit() {
    let point = CGPoint(x: 10, y: 10)
    let candidates: [SweepableTouchTargetPicker.Candidate] = [
      .init(frame: CGRect(x: 100, y: 100, width: 10, height: 10), isSuppressed: false),
      .init(frame: CGRect(x: 200, y: 200, width: 10, height: 10), isSuppressed: false),
    ]
    XCTAssertNil(SweepableTouchTargetPicker.pickIndex(at: point, candidates: candidates))
  }

  func testPickIndex_prefersSmallestAreaAmongHits() {
    let point = CGPoint(x: 50, y: 50)
    let candidates: [SweepableTouchTargetPicker.Candidate] = [
      .init(frame: CGRect(x: 0, y: 0, width: 200, height: 200), isSuppressed: false, debugLabel: "big"),
      .init(frame: CGRect(x: 40, y: 40, width: 30, height: 30), isSuppressed: false, debugLabel: "small"),
    ]
    XCTAssertEqual(SweepableTouchTargetPicker.pickIndex(at: point, candidates: candidates), 1)
  }

  func testPickIndex_tieBreaksByCenterDistance() {
    // Two equal-area hits; pick the one whose center is closer to the touch.
    let point = CGPoint(x: 50, y: 50)
    let candidates2: [SweepableTouchTargetPicker.Candidate] = [
      .init(frame: CGRect(x: 40, y: 40, width: 40, height: 40), isSuppressed: false, debugLabel: "center@60,60"),
      .init(frame: CGRect(x: 30, y: 30, width: 40, height: 40), isSuppressed: false, debugLabel: "center@50,50"),
    ]
    XCTAssertEqual(SweepableTouchTargetPicker.pickIndex(at: point, candidates: candidates2), 1)
  }
}
