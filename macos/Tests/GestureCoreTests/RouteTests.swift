import XCTest
@testable import GestureCore

final class RouteTests: XCTestCase {
    func testStablePointSelectsDisplay() {
        var router = RouteSelector()
        XCTAssertNil(router.update(matches: ["mac-camera:laptop"], at: 1))
        XCTAssertEqual(router.update(matches: ["mac-camera:laptop"], at: 1.31), "mac-camera:laptop")
    }
    func testOnlyCalibratedDisplaySelectsImmediatelyAfterLoss() {
        var router = RouteSelector()
        XCTAssertEqual(router.update(matches: ["laptop"], at: 1, onlyDisplay: true), "laptop")
        XCTAssertNil(router.update(matches: [], at: 1.1, onlyDisplay: true))
        XCTAssertEqual(router.update(matches: ["laptop"], at: 1.2, onlyDisplay: true), "laptop")
    }
    func testSwitchRequiresNewDwell() {
        var router = RouteSelector()
        _ = router.update(matches: ["laptop"], at: 1)
        _ = router.update(matches: ["laptop"], at: 1.31)
        XCTAssertNil(router.update(matches: ["monitor"], at: 2))
        XCTAssertEqual(router.update(matches: ["monitor"], at: 2.31), "monitor")
    }
    func testOutsideLaptopDoesNotAutomaticallyMeanMonitor() {
        var router = RouteSelector()
        _ = router.update(matches: ["laptop"], at: 1)
        _ = router.update(matches: ["laptop"], at: 1.31)
        XCTAssertNil(router.update(matches: [], at: 2))
        XCTAssertNil(router.current)
    }
    func testOverlappingCamerasOrDisplaysAreAmbiguous() {
        var router = RouteSelector()
        _ = router.update(matches: ["laptop"], at: 1)
        _ = router.update(matches: ["laptop"], at: 1.31)
        XCTAssertNil(router.update(matches: ["laptop", "monitor-webcam"], at: 2))
        XCTAssertNil(router.update(matches: ["monitor-webcam"], at: 2.1))
        XCTAssertEqual(router.update(matches: ["monitor-webcam"], at: 2.41), "monitor-webcam")
    }
    func testDragKeepsSourceCameraAndDisplay() {
        var router = RouteSelector()
        _ = router.update(matches: ["laptop"], at: 1)
        _ = router.update(matches: ["laptop"], at: 1.31)
        XCTAssertEqual(router.update(matches: ["monitor"], at: 2, locked: true), "laptop")
        XCTAssertEqual(router.update(matches: [], at: 3, locked: true), "laptop")
        router.reset()
        XCTAssertNil(router.current)
    }
}
