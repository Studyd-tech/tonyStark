import XCTest
@testable import GestureCore

final class CaptureTests: XCTestCase {
    private func frames(pose: Pose = .point) -> [CalibrationFrame] {
        (0..<12).map { i in
            CalibrationFrame(time: 1.45 + Double(i) * 0.045,
                             hand: HandSample(pose: pose, aim: Point(0.3, 0.4), anchor: Point(0.3, 0.6)))
        }
    }
    func testSteadyPointCapturesMedian() {
        switch CalibrationCapture.assess(frames(), at: 2) {
        case .success(let point): XCTAssertEqual(point, Point(0.3, 0.4))
        case .failure(let error): XCTFail("Unexpected failure: \(error)")
        }
    }
    func testLostHandCannotPassUsingEarlierGoodFrames() {
        var input = frames()
        input.append(CalibrationFrame(time: 1.99, hand: nil))
        XCTAssertThrowsError(try CalibrationCapture.assess(input, at: 2).get()) { XCTAssertEqual($0 as? CaptureProblem, .handMissing) }
    }
    func testStalledCameraCannotCaptureOldHandPosition() {
        XCTAssertThrowsError(try CalibrationCapture.assess(frames(), at: 2.3).get()) { XCTAssertEqual($0 as? CaptureProblem, .handMissing) }
    }
    func testOtherPoseNeedsClearRetryInstruction() {
        XCTAssertThrowsError(try CalibrationCapture.assess(frames(pose: .fist), at: 2).get()) { XCTAssertEqual($0 as? CaptureProblem, .pointRequired) }
    }
    func testMovingPointIsRejected() {
        var input = frames()
        input.append(CalibrationFrame(time: 1.99, hand: HandSample(pose: .point, aim: Point(0.5, 0.4), anchor: Point(0.3, 0.6))))
        XCTAssertThrowsError(try CalibrationCapture.assess(input, at: 2).get()) { XCTAssertEqual($0 as? CaptureProblem, .keepStill) }
    }
}
