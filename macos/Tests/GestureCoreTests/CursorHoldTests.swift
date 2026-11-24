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
            if pose != .point { hold.suspend() }
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

    func testDeliberatePointingAwayResumesMovement() {
        var hold = CursorHold(); lock(&hold)
        let destination = Point(560, 300)
        for frame in 0..<19 {
            XCTAssertEqual(hold.update(destination, at: 2.016 + Double(frame) * 0.016), target)
        }
        XCTAssertEqual(hold.update(destination, at: 2.34), destination)
        XCTAssertFalse(hold.isLocked)
    }

    func testGesturesAndMissingFramesBreakResumeDwell() {
        var hold = CursorHold(); lock(&hold)
        let destination = Point(560, 300)
        _ = hold.update(destination, at: 2.1)
        _ = hold.update(destination, at: 2.2)
        hold.suspend()
        XCTAssertEqual(hold.update(destination, at: 2.3), target)
        XCTAssertEqual(hold.update(destination, at: 2.45), target)
        // No observations for a while must not count as continuous pointing.
        XCTAssertEqual(hold.update(destination, at: 3), target)
        XCTAssertTrue(hold.isLocked)
    }

    func testReturningToTargetCancelsResume() {
        var hold = CursorHold(); lock(&hold)
        _ = hold.update(Point(560, 300), at: 2.1)
        _ = hold.update(target, at: 2.2)
        XCTAssertEqual(hold.update(Point(560, 300), at: 2.3), target)
        XCTAssertEqual(hold.update(Point(560, 300), at: 2.45), target)
    }

    func testOcclusionAndOtherPosesDoNotCountTowardLock() {
        var hold = CursorHold()
        for frame in 0...100 {
            _ = hold.update(target, at: Double(frame) * 0.016)
        }
        hold.suspend()
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
