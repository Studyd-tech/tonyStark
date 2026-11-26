import XCTest
import GestureCore

final class DoubleClapGestureTests: XCTestCase {
    private func hands(_ gap: Double, pose: Pose? = .palm, size: Double = 0.1) -> [ClapHand] {
        [ClapHand(center: Point(0.5 - gap * size / 2, 0.5), size: size, pose: pose),
         ClapHand(center: Point(0.5 + gap * size / 2, 0.5), size: size, pose: pose)]
    }

    private let doubleClap: [(Double, Double)] = [(3, 0), (2.4, 0.08), (0.7, 0.16),
        (0.6, 0.24), (3, 0.32), (2.4, 0.4), (0.7, 0.48)]

    func testTwoClapsTriggerOnceWithCooldown() {
        var gesture = DoubleClapGesture()
        var triggers = 0
        for (gap, time) in doubleClap {
            if gesture.update(hands(gap), at: time) { triggers += 1 }
        }
        XCTAssertEqual(triggers, 1)
        XCTAssertTrue(gesture.suppressesOtherGestures(at: 0.5))
        for (gap, time) in doubleClap {
            XCTAssertFalse(gesture.update(hands(gap), at: time + 0.56))
        }
        XCTAssertFalse(gesture.suppressesOtherGestures(at: 2.5))
    }

    func testOneClapAndHoldingHandsTogetherDoNotTrigger() {
        var gesture = DoubleClapGesture()
        for (gap, time) in doubleClap.prefix(3) {
            XCTAssertFalse(gesture.update(hands(gap), at: time))
        }
        XCTAssertTrue(gesture.waitingForSecondClap)
        for frame in 1...15 {
            XCTAssertFalse(gesture.update(hands(0.7), at: 0.16 + Double(frame) * 0.1))
        }
        XCTAssertFalse(gesture.waitingForSecondClap)
    }

    func testMustSeparateBetweenClaps() {
        var gesture = DoubleClapGesture()
        for (gap, time) in [(3.0, 0.0), (0.7, 0.1), (1.5, 0.2), (0.7, 0.3), (1.8, 0.4), (0.6, 0.5)] {
            XCTAssertFalse(gesture.update(hands(gap), at: time))
        }
    }

    func testMissingHandNeverCountsAsContact() {
        var gesture = DoubleClapGesture()
        _ = gesture.update(hands(3), at: 0)
        _ = gesture.update(hands(2.4), at: 0.08)
        XCTAssertFalse(gesture.update(Array(hands(0.7).prefix(1)), at: 0.16))
        XCTAssertFalse(gesture.update(hands(3), at: 0.24))
        XCTAssertFalse(gesture.update(hands(0.7), at: 0.32))
        XCTAssertTrue(gesture.waitingForSecondClap, "Only the observed contact can be the first clap")
    }

    func testBriefContactOcclusionPreservesAnObservedFirstClap() {
        var gesture = DoubleClapGesture()
        for (gap, time) in doubleClap.prefix(3) { _ = gesture.update(hands(gap), at: time) }
        XCTAssertFalse(gesture.update([], at: 0.2))
        XCTAssertFalse(gesture.update(hands(3), at: 0.28))
        XCTAssertTrue(gesture.update(hands(0.7), at: 0.4))
    }

    func testTrackingLossAndStalledFramesCancelPendingClap() {
        var gesture = DoubleClapGesture()
        for (gap, time) in doubleClap.prefix(3) { _ = gesture.update(hands(gap), at: time) }
        _ = gesture.update([], at: 0.4)
        XCTAssertFalse(gesture.waitingForSecondClap)
        XCTAssertFalse(gesture.update(hands(3), at: 0.5))
        XCTAssertFalse(gesture.update(hands(0.7), at: 0.6))
    }

    func testSlowApproachDoesNotCount() {
        var gesture = DoubleClapGesture()
        for frame in 0...20 {
            let gap = 3 - Double(frame) * 0.12
            XCTAssertFalse(gesture.update(hands(gap), at: Double(frame) * 0.1))
        }
        XCTAssertFalse(gesture.waitingForSecondClap)
    }

    func testHandOrderAndDistanceFromCameraDoNotChangeRecognition() {
        for size in [0.05, 0.1, 0.2] {
            var gesture = DoubleClapGesture()
            var triggers = 0
            for (index, sample) in doubleClap.enumerated() {
                var pair = hands(sample.0, size: size)
                if index % 2 == 1 { pair.reverse() }
                if gesture.update(pair, at: sample.1) { triggers += 1 }
            }
            XCTAssertEqual(triggers, 1)
        }
    }

    func testFistsAndPointingCannotStartClaps() {
        for pose in [Pose.fist, .point, .pinch, .twoFingers] {
            var gesture = DoubleClapGesture()
            for (gap, time) in doubleClap {
                XCTAssertFalse(gesture.update(hands(gap, pose: pose), at: time))
            }
        }
    }

    func testClappingSuppressesBrowserCloseAndInverseMissionGesture() {
        var clap = DoubleClapGesture()
        var other = TwoHandGesture()
        var commands: [TwoHandGesture.Command] = []
        for (gap, time, pose) in [(3.0, 0.0, Pose.palm), (3, 0.15, .palm), (3, 0.25, .palm),
            (2.4, 0.33, .palm), (0.7, 0.41, .fist), (3, 0.49, .palm), (2.4, 0.57, .palm),
            (0.7, 0.65, .fist), (0.7, 0.8, .fist), (3, 0.95, .palm), (3, 1.15, .palm)] {
            let recognized = clap.update(hands(gap, pose: pose), at: time)
            if recognized || clap.suppressesOtherGestures(at: time) {
                other = TwoHandGesture()
                if recognized { commands.append(.missionControl) }
            } else if let action = other.update([pose, pose], at: time) { commands.append(action) }
        }
        XCTAssertEqual(commands, [.missionControl])
    }

    func testStationaryOpenHandsLeaveOtherGesturesAvailable() {
        var clap = DoubleClapGesture()
        for frame in 0...30 {
            XCTAssertFalse(clap.update(hands(3), at: Double(frame) * 0.08))
            XCTAssertFalse(clap.suppressesOtherGestures(at: Double(frame) * 0.08))
        }
    }

    func testPalmGeometryRequiresLandmarksAndCorrectsAspectRatio() {
        let image: [String: Point] = ["wrist": Point(0.4, 0.8), "indexMCP": Point(0.38, 0.6),
            "middleMCP": Point(0.4, 0.6), "littleMCP": Point(0.45, 0.62)]
        let hand = ClapHand(image: image, pose: .palm, aspectRatio: 2)
        XCTAssertEqual(hand?.size ?? 0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(hand?.center.x ?? 0, 0.815, accuracy: 0.0001)
        XCTAssertNil(ClapHand(image: [:], pose: .palm, aspectRatio: 1))
        XCTAssertNil(ClapHand(image: image, pose: .palm, aspectRatio: .nan))
    }
}
