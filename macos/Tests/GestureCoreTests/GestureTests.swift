import XCTest
@testable import GestureCore

final class GestureTests: XCTestCase {
    private func hand(_ pose: Pose, _ x: Double = 0.5) -> HandSample {
        HandSample(pose: pose, aim: Point(x, 0.3), anchor: Point(x, 0.6))
    }
    private func arm(_ machine: inout GestureMachine, at time: Double = 1) {
        _ = machine.update(hand(.point), at: time)
        _ = machine.update(hand(.point), at: time + 0.3)
        _ = machine.update(hand(.point), at: time + 0.6)
        _ = machine.update(hand(.point), at: time + 0.8)
        XCTAssertTrue(machine.armed)
    }
    func testNoCommandsBeforeDeliberateArming() {
        var machine = GestureMachine()
        for (i, pose) in [Pose.fist, .fist, .palm, .palm, .pinch, .pinch].enumerated() {
            XCTAssertTrue(machine.update(hand(pose), at: Double(i) * 0.2).isEmpty)
        }
        XCTAssertFalse(machine.armed)
    }
    func testPointDwellMustBeContinuous() {
        var machine = GestureMachine()
        _ = machine.update(hand(.point), at: 1)
        _ = machine.update(hand(.point), at: 1.3)
        _ = machine.update(nil, at: 1.4)
        XCTAssertFalse(machine.update(hand(.point), at: 1.5).contains(.armed))
        XCTAssertFalse(machine.armed)
    }
    func testBriefPointingOcclusionPausesDwellWithoutStartingOver() {
        var machine = GestureMachine()
        _ = machine.update(hand(.point), at: 1)
        _ = machine.update(hand(.point), at: 1.3)
        _ = machine.update(hand(.point), at: 1.62)
        _ = machine.update(nil, at: 1.67)
        XCTAssertTrue(machine.update(hand(.point), at: 1.77).isEmpty)
        XCTAssertFalse(machine.armed, "Time without a detected hand should not count toward arming")
        XCTAssertEqual(machine.update(hand(.point), at: 1.91), [.armed, .cursor(Point(0.5, 0.3))])
    }

    func testLongerPointingOcclusionRequiresANewHold() {
        var machine = GestureMachine()
        _ = machine.update(hand(.point), at: 1)
        _ = machine.update(hand(.point), at: 1.32)
        _ = machine.update(hand(.point), at: 1.65)
        _ = machine.update(nil, at: 1.7)
        XCTAssertTrue(machine.update(hand(.point), at: 1.9).isEmpty)
        XCTAssertTrue(machine.update(hand(.point), at: 2.2).isEmpty)
    }
    func testFistThenPalmTriggersOnce() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.fist), at: 2)
        _ = machine.update(hand(.fist), at: 2.3)
        _ = machine.update(hand(.palm), at: 2.4)
        XCTAssertTrue(machine.update(hand(.palm), at: 2.61).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 2.9).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 3.2).isEmpty)
        XCTAssertEqual(machine.update(hand(.palm), at: 3.29), [.missionControl])
        XCTAssertTrue(machine.update(hand(.palm), at: 3.5).isEmpty)
    }
    func testFistPalmFistClicksOnceWithoutMovingOrOpeningMissionControl() {
        var machine = GestureMachine(); arm(&machine)
        XCTAssertEqual(machine.update(hand(.point, 0.7), at: 1.9), [.cursor(Point(0.7, 0.3))])
        for (pose, time) in [(Pose.fist, 2.0), (.fist, 2.25), (.palm, 2.32), (.palm, 2.52),
                             (.palm, 2.83), (.other, 3.04), (.fist, 3.14)] {
            XCTAssertTrue(machine.update(hand(pose, 0.1), at: time).isEmpty)
        }
        XCTAssertEqual(machine.update(hand(.fist, 0.1), at: 3.38), [.click])
        XCTAssertTrue(machine.update(hand(.fist), at: 3.6).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 3.7).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 3.95).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 4.25).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 4.55).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 4.75).isEmpty)
    }
    func testLostHandCancelsPendingClick() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.fist), at: 2)
        _ = machine.update(hand(.fist), at: 2.25)
        _ = machine.update(hand(.palm), at: 2.32)
        _ = machine.update(hand(.palm), at: 2.52)
        _ = machine.update(nil, at: 2.6)
        XCTAssertTrue(machine.update(hand(.fist), at: 2.66).isEmpty)
        XCTAssertTrue(machine.update(hand(.fist), at: 2.9).isEmpty)
    }
    func testPalmAloneDoesNotOpenMissionControl() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.palm), at: 2)
        XCTAssertFalse(machine.update(hand(.palm), at: 2.3).contains(.missionControl))
    }
    func testShortFistDoesNotPrimeMissionControl() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.fist), at: 2)
        _ = machine.update(hand(.palm), at: 2.1)
        XCTAssertFalse(machine.update(hand(.palm), at: 2.35).contains(.missionControl))
    }
    func testPointPalmFistSelectsThenMinimizesOnce() {
        var machine = GestureMachine(); arm(&machine)
        XCTAssertEqual(machine.update(hand(.point, 0.7), at: 1.9), [.cursor(Point(0.7, 0.3))])
        XCTAssertTrue(machine.update(hand(.other), at: 2.0).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm, 0.2), at: 2.1).isEmpty)
        XCTAssertEqual(machine.update(hand(.palm, 0.2), at: 2.31), [.selectWindow])
        XCTAssertTrue(machine.update(hand(.palm), at: 2.55).isEmpty)
        XCTAssertTrue(machine.update(hand(.point), at: 2.6).isEmpty, "A transitional point should leave the selected window in place")
        XCTAssertTrue(machine.update(hand(.fist), at: 2.7).isEmpty)
        XCTAssertEqual(machine.update(hand(.fist), at: 2.94), [.minimizeSelectedWindow])
        XCTAssertTrue(machine.update(hand(.fist), at: 3.15).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 3.25).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 3.5).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 3.8).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 4.1).isEmpty)
        XCTAssertTrue(machine.update(hand(.palm), at: 4.3).isEmpty)
    }

    func testPointingAgainCancelsPendingMinimize() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.palm), at: 2)
        XCTAssertEqual(machine.update(hand(.palm), at: 2.2), [.selectWindow])
        _ = machine.update(hand(.point), at: 2.3)
        XCTAssertEqual(machine.update(hand(.point), at: 2.5), [.cursor(Point(0.5, 0.3))])
        _ = machine.update(hand(.fist), at: 2.6)
        XCTAssertTrue(machine.update(hand(.fist), at: 2.85).isEmpty)
    }

    func testTrackingLossCancelsPendingMinimize() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.palm), at: 2)
        XCTAssertEqual(machine.update(hand(.palm), at: 2.2), [.selectWindow])
        _ = machine.update(nil, at: 2.25)
        _ = machine.update(hand(.fist), at: 2.3)
        XCTAssertTrue(machine.update(hand(.fist), at: 2.55).isEmpty)
    }
    func testPinchStartsAfterDwellAndUsesPalmAnchor() {
        var machine = GestureMachine(); arm(&machine)
        XCTAssertFalse(machine.update(hand(.pinch), at: 2).contains(.grab(Point(0.5, 0.6))))
        XCTAssertTrue(machine.update(hand(.pinch), at: 2.2).contains(.grab(Point(0.5, 0.6))))
        XCTAssertEqual(machine.update(hand(.pinch, 0.6), at: 2.3), [.drag(Point(0.6, 0.6))])
        XCTAssertTrue(machine.update(hand(.palm), at: 2.4).isEmpty)
        XCTAssertEqual(machine.update(hand(.palm), at: 2.56), [.release])
        XCTAssertFalse(machine.dragging)
    }

    private func scrollHand(y: Double) -> HandSample {
        HandSample(pose: .twoFingers, aim: Point(0.8, 0.2), anchor: Point(0.6, y))
    }

    func testTwoFingerScrollRequiresAnArmedPointerAndStablePose() {
        var machine = GestureMachine()
        XCTAssertTrue(machine.update(scrollHand(y: 0.6), at: 0).isEmpty)
        XCTAssertTrue(machine.update(scrollHand(y: 0.7), at: 0.3).isEmpty)
        arm(&machine)
        XCTAssertTrue(machine.update(scrollHand(y: 0.6), at: 2).isEmpty)
        XCTAssertTrue(machine.update(scrollHand(y: 0.62), at: 2.1).isEmpty)
        XCTAssertEqual(machine.update(scrollHand(y: 0.62), at: 2.25), [.scrollStarted])
        XCTAssertTrue(machine.scrolling)
    }

    func testScrollUsesVerticalMotionAndStopsBeforePointerMoves() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(scrollHand(y: 0.6), at: 2)
        XCTAssertEqual(machine.update(scrollHand(y: 0.6), at: 2.25), [.scrollStarted])
        XCTAssertTrue(machine.update(scrollHand(y: 0.603), at: 2.3).isEmpty)
        XCTAssertEqual(machine.update(scrollHand(y: 0.62), at: 2.35), [.scroll(34)])
        XCTAssertEqual(machine.update(scrollHand(y: 0.59), at: 2.4), [.scroll(-51)])
        XCTAssertTrue(machine.update(hand(.point), at: 2.45).isEmpty)
        XCTAssertEqual(machine.update(hand(.point), at: 2.61), [.scrollEnded])
        XCTAssertEqual(machine.update(hand(.point), at: 2.65), [.cursor(Point(0.5, 0.3))])
    }

    func testLosingTrackingStopsScrollAndRequiresAFreshAnchor() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(scrollHand(y: 0.6), at: 2)
        _ = machine.update(scrollHand(y: 0.6), at: 2.25)
        XCTAssertEqual(machine.update(nil, at: 2.3), [.scrollEnded])
        XCTAssertTrue(machine.update(scrollHand(y: 0.35), at: 2.35).isEmpty)
        XCTAssertEqual(machine.update(scrollHand(y: 0.35), at: 2.61), [.scrollStarted])
        XCTAssertTrue(machine.update(scrollHand(y: 0.35), at: 2.66).isEmpty)
        XCTAssertEqual(machine.reset(), [.scrollEnded, .disarmed])
    }
    func testTrackingTimeoutReleasesAndDisarms() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.pinch), at: 2)
        _ = machine.update(hand(.pinch), at: 2.2)
        XCTAssertEqual(machine.expire(at: 2.7), [.release, .disarmed])
        XCTAssertFalse(machine.armed)
        XCTAssertTrue(machine.expire(at: 3).isEmpty)
    }
    func testBriefOcclusionDoesNotMoveOrDropWindow() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.pinch), at: 2)
        _ = machine.update(hand(.pinch), at: 2.2)
        XCTAssertTrue(machine.update(nil, at: 2.3).isEmpty)
        XCTAssertEqual(machine.update(hand(.pinch, 0.6), at: 2.4), [.drag(Point(0.6, 0.6))])
    }
    func testStaleReturningHandCannotContinueGrab() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.pinch), at: 2)
        _ = machine.update(hand(.pinch), at: 2.2)
        XCTAssertEqual(machine.update(hand(.pinch), at: 3), [.release, .disarmed])
    }
    func testManualResetReleasesBeforeDisarming() {
        var machine = GestureMachine(); arm(&machine)
        _ = machine.update(hand(.pinch), at: 2)
        _ = machine.update(hand(.pinch), at: 2.2)
        XCTAssertEqual(machine.reset(), [.release, .disarmed])
    }
    func testClassifierRequiresAllCriticalLandmarks() {
        XCTAssertNil(HandGeometry(joints: ["indexTip": Point(0.4, 0.3)]).sample())
    }
    func testThreeFingerPinchRequiresBothFingertips() {
        var joints: [String: Point] = ["wrist": Point(0.5, 0.8), "middleMCP": Point(0.5, 0.6),
            "indexMCP": Point(0.45, 0.6), "ringMCP": Point(0.55, 0.6), "littleMCP": Point(0.6, 0.62),
            "thumbTip": Point(0.45, 0.45), "indexTip": Point(0.46, 0.44), "middleTip": Point(0.49, 0.44),
            "ringTip": Point(0.55, 0.7), "littleTip": Point(0.6, 0.72)]
        XCTAssertEqual(HandGeometry(joints: joints).sample()?.pose, .pinch)
        joints["middleTip"] = Point(0.5, 0.25)
        XCTAssertNotEqual(HandGeometry(joints: joints).sample()?.pose, .pinch)
    }
    func testFoldedFistIsNotMisreadAsThreeFingerPinch() {
        let joints: [String: Point] = ["wrist": Point(0.5, 0.8), "middleMCP": Point(0.5, 0.6),
            "indexMCP": Point(0.45, 0.6), "ringMCP": Point(0.55, 0.6), "littleMCP": Point(0.6, 0.62),
            "thumbTip": Point(0.49, 0.7), "indexTip": Point(0.47, 0.7), "middleTip": Point(0.51, 0.7),
            "ringTip": Point(0.55, 0.7), "littleTip": Point(0.6, 0.72)]
        XCTAssertEqual(HandGeometry(joints: joints).sample()?.pose, .fist)
    }
    private var shortenedPoint: [String: Point] {
        ["wrist": Point(0.5, 0.8), "middleMCP": Point(0.5, 0.6), "indexMCP": Point(0.45, 0.6),
         "ringMCP": Point(0.55, 0.6), "littleMCP": Point(0.6, 0.62), "thumbTip": Point(0.42, 0.7),
         "indexTip": Point(0.5, 0.55), "middleTip": Point(0.5, 0.69), "ringTip": Point(0.55, 0.7), "littleTip": Point(0.6, 0.72)]
    }
    func testForeshortenedIndexCanPointRelativeToFoldedFingers() {
        XCTAssertEqual(HandGeometry(joints: shortenedPoint).sample()?.pose, .point)
    }
    func testHiddenPinkyDoesNotDiscardPointingHand() {
        var joints = shortenedPoint
        joints.removeValue(forKey: "littleTip")
        XCTAssertEqual(HandGeometry(joints: joints).sample()?.pose, .point)
    }
    func testTwoRaisedFingersAreNotAnIndexPoint() {
        var joints = shortenedPoint
        joints["middleTip"] = Point(0.5, 0.25)
        XCTAssertNotEqual(HandGeometry(joints: joints).sample()?.pose, .point)
    }
    func testMissingIndexTipCannotControlCursor() {
        var joints = shortenedPoint
        joints.removeValue(forKey: "indexTip")
        XCTAssertNil(HandGeometry(joints: joints).sample())
    }
}

final class CalibrationTests: XCTestCase {
    let corners = [Point(0, 0), Point(1, 0), Point(1, 1), Point(0, 1)]
    func testMapsFourCornersAndCenter() throws {
        let input = [Point(0.2, 0.2), Point(0.8, 0.2), Point(0.8, 0.8), Point(0.2, 0.8)]
        let mapping = try XCTUnwrap(Calibration(camera: input, desktop: corners))
        for (p, q) in zip(input, corners) {
            let mapped = try XCTUnwrap(mapping.map(p))
            XCTAssertEqual(mapped.x, q.x, accuracy: 1e-8); XCTAssertEqual(mapped.y, q.y, accuracy: 1e-8)
        }
        let center = try XCTUnwrap(mapping.map(Point(0.5, 0.5)))
        XCTAssertEqual(center.x, 0.5, accuracy: 1e-8); XCTAssertEqual(center.y, 0.5, accuracy: 1e-8)
    }
    func testAngledQuadrilateralMapsToDisplayCorners() throws {
        let input = [Point(0.15, 0.23), Point(0.85, 0.1), Point(0.75, 0.8), Point(0.25, 0.9)]
        let mapping = try XCTUnwrap(Calibration(camera: input, desktop: corners))
        for (p, q) in zip(input, corners) {
            let mapped = try XCTUnwrap(mapping.map(p))
            XCTAssertEqual(mapped.x, q.x, accuracy: 1e-8); XCTAssertEqual(mapped.y, q.y, accuracy: 1e-8)
        }
    }
    func testRejectsOverlappingAndCrossedCalibration() {
        XCTAssertNil(Calibration(camera: Array(repeating: Point(0.5, 0.5), count: 4), desktop: corners))
        XCTAssertNil(Calibration(camera: [corners[0], corners[2], corners[1], corners[3]], desktop: corners))
    }
    func testSavedCalibrationRoundTrip() throws {
        let mapping = try XCTUnwrap(Calibration(camera: corners, desktop: corners))
        let restored = try JSONDecoder().decode(Calibration.self, from: JSONEncoder().encode(mapping))
        let mapped = try XCTUnwrap(restored.map(Point(0.37, 0.61)))
        XCTAssertEqual(mapped.x, 0.37, accuracy: 1e-8)
        XCTAssertEqual(mapped.y, 0.61, accuracy: 1e-8)
    }
    func testCursorFilterUsesElapsedTime() {
        var filter = CursorFilter()
        XCTAssertEqual(filter.update(Point(0, 0), at: 1), Point(0, 0))
        let next = filter.update(Point(1, 1), at: 1.03)
        XCTAssertGreaterThan(next.x, 0); XCTAssertLessThan(next.x, 1)
        filter.reset()
        XCTAssertEqual(filter.update(Point(1, 1), at: 2), Point(1, 1))
    }
}
