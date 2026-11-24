import XCTest
@testable import GestureCore

final class SpatialTests: XCTestCase {
    private let image = ["wrist": Point(0.5, 0.7), "middleMCP": Point(0.5, 0.55), "indexTip": Point(0.45, 0.52)]
    private func hand(indexOpen: Bool = true, allOpen: Bool = false) -> [String: Point3D] {
        var joints = ["wrist": Point3D(0, 0, 0), "thumbTip": Point3D(-0.055, 0.035, 0.02)]
        for (i, finger) in ["index", "middle", "ring", "little"].enumerated() {
            let x = Double(i - 1) * 0.02
            joints[finger + "MCP"] = Point3D(x, 0.055, 0)
            if allOpen || (finger == "index" && indexOpen) {
                joints[finger + "PIP"] = Point3D(x, 0.08, 0)
                joints[finger + "DIP"] = Point3D(x, 0.10, 0)
                joints[finger + "Tip"] = Point3D(x, 0.12, 0)
            } else {
                joints[finger + "PIP"] = Point3D(x, 0.07, -0.015)
                joints[finger + "DIP"] = Point3D(x, 0.045, -0.025)
                joints[finger + "Tip"] = Point3D(x, 0.035, -0.015)
            }
        }
        return joints
    }
    func testPointSurvivesRotationStraightTowardCamera() {
        let world = hand()
        for degrees in stride(from: 0.0, through: 180.0, by: 15) {
            let a = degrees * .pi / 180
            let rotated = world.mapValues { p in Point3D(p.x, p.y * cos(a) - p.z * sin(a), p.y * sin(a) + p.z * cos(a)) }
            XCTAssertEqual(SpatialHandGeometry(image: image, world: rotated).sample()?.pose, .point, "angle \(degrees)")
        }
    }
    func testCollapsedImageProjectionDoesNotTurn3DPointIntoFist() {
        let collapsed = ["wrist": Point(0.5, 0.5), "middleMCP": Point(0.5, 0.5), "indexTip": Point(0.5, 0.5)]
        XCTAssertEqual(SpatialHandGeometry(image: collapsed, world: hand()).sample()?.pose, .point)
    }
    func testTrueFistRemainsFist() {
        XCTAssertEqual(SpatialHandGeometry(image: image, world: hand(indexOpen: false)).sample()?.pose, .fist)
    }
    func testIndexAndMiddleExtendedRecognizeTwoFingerScroll() {
        var world = hand()
        let open = hand(allOpen: true)
        for joint in ["middlePIP", "middleDIP", "middleTip"] { world[joint] = open[joint] }
        XCTAssertEqual(SpatialHandGeometry(image: image, world: world).sample()?.pose, .twoFingers)
    }
    func testOpenPalmAndThreeFingerPinchRemainDistinct() {
        XCTAssertEqual(SpatialHandGeometry(image: image, world: hand(allOpen: true)).sample()?.pose, .palm)
        var pinch = hand()
        pinch["indexTip"] = Point3D(0, 0.085, -0.03)
        pinch["middleTip"] = Point3D(0.005, 0.085, -0.03)
        pinch["thumbTip"] = Point3D(0.002, 0.085, -0.031)
        XCTAssertEqual(SpatialHandGeometry(image: image, world: pinch).sample()?.pose, .pinch)
    }
    func testIndexOnlyDetectionCannotInventFullHandPose() {
        XCTAssertNil(SpatialHandGeometry(image: ["indexTip": Point(0.4, 0.4)], world: ["indexTip": Point3D(0, 0, 0)]).sample())
    }
    func testInvalidDepthIsRejected() {
        var joints = hand(); joints["indexTip"] = Point3D(0, 0, .nan)
        XCTAssertNil(SpatialHandGeometry(image: image, world: joints).sample())
    }
}
