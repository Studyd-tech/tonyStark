import XCTest
import GestureCore

final class BrowserCloseSequenceTests: XCTestCase {
    func testOneGestureClosesTabAndQuickRepeatClosesSameWindow() {
        var sequence = BrowserCloseSequence<String>()
        XCTAssertEqual(sequence.action(for: "chrome:window-a", at: 1), .tab)
        sequence.recordSuccess(.tab, target: "chrome:window-a", at: 1)
        XCTAssertEqual(sequence.action(for: "chrome:window-a", at: 2.3), .window)
        sequence.recordSuccess(.window, target: "chrome:window-a", at: 2.3)
        XCTAssertEqual(sequence.action(for: "chrome:window-a", at: 2.5), .tab)
    }

    func testSlowRepeatClosesAnotherTab() {
        var sequence = BrowserCloseSequence<String>()
        sequence.recordSuccess(.tab, target: "chrome:window-a", at: 1)
        XCTAssertEqual(sequence.action(for: "chrome:window-a", at: 4.01), .tab)
    }

    func testRepeatInAnotherWindowOrBrowserCannotCloseWindow() {
        var sequence = BrowserCloseSequence<String>()
        sequence.recordSuccess(.tab, target: "chrome:window-a", at: 1)
        XCTAssertEqual(sequence.action(for: "chrome:window-b", at: 2), .tab)
        XCTAssertEqual(sequence.action(for: "safari:window-a", at: 2), .tab)
    }

    func testFailureAndPauseClearRepeat() {
        var sequence = BrowserCloseSequence<String>()
        sequence.recordSuccess(.tab, target: "chrome:window-a", at: 1)
        sequence.reset()
        XCTAssertEqual(sequence.action(for: "chrome:window-a", at: 2), .tab)
    }

    func testMerelyRequestingActionDoesNotArmRepeat() {
        let sequence = BrowserCloseSequence<String>()
        XCTAssertEqual(sequence.action(for: "chrome:window-a", at: 1), .tab)
        XCTAssertEqual(sequence.action(for: "chrome:window-a", at: 2), .tab)
    }

    func testTwoCompleteHandGesturesProduceTabThenWindow() {
        var gesture = TwoHandGesture()
        var sequence = BrowserCloseSequence<String>()
        var actions: [BrowserCloseAction] = []
        for (pose, time) in [(Pose.palm, 1.0), (.palm, 1.24), (.fist, 1.4), (.fist, 1.6),
                             (.fist, 1.8), (.palm, 2.0), (.palm, 2.24), (.fist, 2.4), (.fist, 2.6)] {
            if gesture.update([pose, pose], at: time) == .closeTab {
                let action = sequence.action(for: "chrome:window-a", at: time)
                actions.append(action)
                sequence.recordSuccess(action, target: "chrome:window-a", at: time)
            }
        }
        XCTAssertEqual(actions, [.tab, .window])
    }
}
