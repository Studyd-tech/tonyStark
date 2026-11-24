import XCTest
import GestureCore

final class TwoHandGestureTests: XCTestCase {
    func testBothFistsThenBothPalmsOpenMissionControlOnce() {
        var gesture = TwoHandGesture()
        XCTAssertNil(gesture.update([.fist, .fist], at: 1))
        XCTAssertTrue(gesture.suppressesSingleHand(at: 1))
        XCTAssertNil(gesture.update([.fist, .fist], at: 1.24))
        XCTAssertEqual(gesture.readyCommand, .missionControl)
        XCTAssertNil(gesture.update([.palm, .fist], at: 1.34))
        XCTAssertNil(gesture.update([.fist, .palm], at: 1.45))
        XCTAssertNil(gesture.update([.palm, .palm], at: 1.55))
        XCTAssertEqual(gesture.update([.palm, .palm], at: 1.75), .missionControl)
        XCTAssertNil(gesture.update([.palm, .palm], at: 1.95))
        XCTAssertNil(gesture.update([.palm, .palm], at: 2.15))
        XCTAssertNil(gesture.readyCommand)
    }

    func testSingleFistNeverPrimesTheTwoHandGesture() {
        var gesture = TwoHandGesture()
        XCTAssertNil(gesture.update([.fist], at: 1))
        XCTAssertNil(gesture.update([.fist, .palm], at: 1.24))
        XCTAssertNil(gesture.update([.palm, .palm], at: 1.45))
        XCTAssertNil(gesture.update([.palm, .palm], at: 1.65))
    }

    func testLosingAHandClearsGestureAndBrieflySuppressesSingleHandActions() {
        var gesture = TwoHandGesture()
        _ = gesture.update([.fist, .fist], at: 1)
        _ = gesture.update([.fist, .fist], at: 1.24)
        XCTAssertNil(gesture.update([.palm], at: 1.34))
        XCTAssertTrue(gesture.suppressesSingleHand(at: 1.34))
        XCTAssertFalse(gesture.suppressesSingleHand(at: 1.6))
        XCTAssertNil(gesture.update([.palm, .palm], at: 1.62))
        XCTAssertNil(gesture.update([.palm, .palm], at: 1.85))
    }

    func testStalledCameraCannotCompleteAnOldGesture() {
        var gesture = TwoHandGesture()
        _ = gesture.update([.fist, .fist], at: 1)
        _ = gesture.update([.fist, .fist], at: 1.24)
        XCTAssertNil(gesture.update([.palm, .palm], at: 1.7))
        XCTAssertNil(gesture.update([.palm, .palm], at: 1.9))
    }

    func testTwoOpenPalmsThenTwoFistsCloseOneTab() {
        var gesture = TwoHandGesture()
        XCTAssertNil(gesture.update([.palm, .palm], at: 1))
        XCTAssertNil(gesture.update([.palm, .palm], at: 1.24))
        XCTAssertEqual(gesture.readyCommand, .closeTab)
        XCTAssertNil(gesture.update([.palm, .fist], at: 1.32))
        XCTAssertNil(gesture.update([nil, .fist], at: 1.4))
        XCTAssertNil(gesture.update([.fist, .fist], at: 1.48))
        XCTAssertEqual(gesture.update([.fist, .fist], at: 1.69), .closeTab)
        XCTAssertNil(gesture.update([.fist, .fist], at: 1.88))
        XCTAssertNil(gesture.readyCommand)
    }

    func testEndingFistsDoNotArmMissionControlAndTheNextPalmHoldCanArmAnotherClose() {
        var gesture = TwoHandGesture()
        _ = gesture.update([.palm, .palm], at: 1)
        _ = gesture.update([.palm, .palm], at: 1.24)
        _ = gesture.update([.fist, .fist], at: 1.4)
        XCTAssertEqual(gesture.update([.fist, .fist], at: 1.6), .closeTab)
        XCTAssertNil(gesture.update([.fist, .fist], at: 1.86))
        XCTAssertNil(gesture.readyCommand)
        XCTAssertNil(gesture.update([.palm, .palm], at: 2))
        XCTAssertNil(gesture.update([.palm, .palm], at: 2.24))
        XCTAssertEqual(gesture.readyCommand, .closeTab)
        _ = gesture.update([.fist, .fist], at: 2.38)
        XCTAssertEqual(gesture.update([.fist, .fist], at: 2.59), .closeTab)
    }

    func testPointsAndOneFistCannotCloseATab() {
        var gesture = TwoHandGesture()
        _ = gesture.update([.palm, .palm], at: 1)
        _ = gesture.update([.palm, .palm], at: 1.24)
        XCTAssertNil(gesture.update([.point, .point], at: 1.42))
        XCTAssertNil(gesture.update([.point, .point], at: 1.63))
        XCTAssertNil(gesture.update([.fist], at: 1.72))
        XCTAssertNil(gesture.update([.fist, .fist], at: 1.82))
        XCTAssertNil(gesture.update([.fist, .fist], at: 2.03))
    }
}
