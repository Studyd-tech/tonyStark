import XCTest
@testable import GestureCore

final class CursorHoldTests: XCTestCase {
    private let target = Point(500, 300)

    private func lock(_ hold: inout CursorHold) {
        for frame in 0...125 {
            _ = hold.update(target, at: Double(frame) * 0.016)
        }
        XCTAssertTrue(hold.isLocked)
    }

    func testTwoSecondsOfSteadyPointingLocksDespiteSmallJitter() {
        var hold = CursorHold()
        for frame in 0..<125 {
            _ = hold.update(Point(500 + Double(frame % 3), 300), at: Double(frame) * 0.016)
            XCTAssertFalse(hold.isLocked)
        }
        XCTAssertEqual(hold.update(target, at: 2), target)
        XCTAssertTrue(hold.isLocked)
        XCTAssertEqual(hold.update(Point(507, 304), at: 2.1), target)
    }

    func testContinuousMovementDoesNotLock() {
        var hold = CursorHold()
        for frame in 0...200 {
            let point = Point(Double(frame) * 3, 300)
            XCTAssertEqual(hold.update(point, at: Double(frame) * 0.016), point)
            XCTAssertFalse(hold.isLocked)
        }
    }

    func testPalmTransitionKeepsTheClickAtTheHeldTarget() {
        var machine = GestureMachine()
        var hold = CursorHold()
        var cursor: Point?
        func feed(_ pose: Pose, x: Double, at time: Double) -> [GestureAction] {
            hold.observePose(pose, at: time)
            let sample = HandSample(pose: pose, aim: Point(x, 0.3), anchor: Point(0.5, 0.6))
            let actions = machine.update(sample, at: time)
            for action in actions {
                if case .cursor(let aim) = action {
                    cursor = hold.update(Point(aim.x * 1000, aim.y * 1000), at: time)
                }
            }
            return actions
        }
        for frame in 0...190 {
            _ = feed(.point, x: 0.5, at: Double(frame) * 0.016)
        }
        XCTAssertTrue(hold.isLocked)
        // As the fingers unfold the detector can briefly still report pointing.
        for frame in 191...200 {
            _ = feed(.point, x: 0.7, at: Double(frame) * 0.016)
            XCTAssertEqual(cursor, target)
        }
        _ = feed(.palm, x: 0.8, at: 3.22)
        XCTAssertEqual(feed(.palm, x: 0.8, at: 3.42), [.selectWindow])
        XCTAssertEqual(cursor, target)
        XCTAssertTrue(hold.isLocked)
    }

    func testMovementWithoutLeavingPointingNeverUnlocks() {
        var hold = CursorHold(); lock(&hold)
        let destination = Point(560, 300)
        for frame in 0..<100 {
            XCTAssertEqual(hold.update(destination, at: 2.016 + Double(frame) * 0.016), target)
        }
        XCTAssertTrue(hold.isLocked)
    }

    private func openPalm(_ hold: inout CursorHold) {
        for frame in 0...20 {
            hold.observePose(.palm, at: 2.016 + Double(frame) * 0.016)
        }
        XCTAssertTrue(hold.isLocked)
    }

    func testFreshSustainedPointResumesEvenAtSameTarget() {
        var hold = CursorHold(); lock(&hold); openPalm(&hold)
        for frame in 0..<25 {
            XCTAssertEqual(hold.update(target, at: 2.35 + Double(frame) * 0.016), target)
            XCTAssertTrue(hold.isLocked)
        }
        _ = hold.update(target, at: 2.76)
        XCTAssertFalse(hold.isLocked)
        let destination = Point(560, 300)
        XCTAssertEqual(hold.update(destination, at: 2.78), destination)
    }

    func testPalmAndBriefMisreadPointsKeepTargetLocked() {
        var hold = CursorHold(); lock(&hold); openPalm(&hold)
        let destination = Point(800, 600)
        for frame in 0...15 {
            XCTAssertEqual(hold.update(destination, at: 2.35 + Double(frame) * 0.016), target)
        }
        for frame in 0...150 {
            hold.observePose(.palm, at: 2.61 + Double(frame) * 0.016)
            XCTAssertTrue(hold.isLocked)
        }
        XCTAssertEqual(hold.update(destination, at: 5.03), target)
    }

    func testGesturesAndMissingFramesBreakFreshPointDwell() {
        var hold = CursorHold(); lock(&hold)
        openPalm(&hold)
        let destination = Point(560, 300)
        _ = hold.update(destination, at: 2.35)
        _ = hold.update(destination, at: 2.5)
        hold.observePose(.palm, at: 2.6)
        XCTAssertEqual(hold.update(destination, at: 2.7), target)
        XCTAssertEqual(hold.update(destination, at: 2.85), target)
        // No observations for a while must not count as continuous pointing.
        XCTAssertEqual(hold.update(destination, at: 3.2), target)
        XCTAssertTrue(hold.isLocked)
    }

    func testMissingOrUncertainPoseCannotAuthorizeUnlock() {
        var hold = CursorHold(); lock(&hold)
        hold.observePose(nil, at: 2.016)
        for frame in 0...30 {
            hold.observePose(.other, at: 2.032 + Double(frame) * 0.016)
        }
        for frame in 0...50 {
            XCTAssertEqual(hold.update(Point(800, 600), at: 2.53 + Double(frame) * 0.016), target)
        }
        XCTAssertTrue(hold.isLocked)
    }

    func testOcclusionAndOtherPosesDoNotCountTowardLock() {
        var hold = CursorHold()
        for frame in 0...100 {
            _ = hold.update(target, at: Double(frame) * 0.016)
        }
        hold.observePose(nil, at: 1.65)
        _ = hold.update(target, at: 1.7)
        _ = hold.update(target, at: 1.8)
        _ = hold.update(target, at: 2.2)
        XCTAssertFalse(hold.isLocked)
    }

    func testResetClearsHeldTarget() {
        var hold = CursorHold(); lock(&hold)
        hold.reset()
        let destination = Point(800, 600)
        XCTAssertEqual(hold.update(destination, at: 2.1), destination)
        XCTAssertFalse(hold.isLocked)
    }
}
