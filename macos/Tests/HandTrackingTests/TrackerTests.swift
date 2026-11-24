import XCTest
import AppKit
import HandTracking
import GestureCore

final class TrackerTests: XCTestCase {
    private func tracker() throws -> MediaPipeTracker {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let assets = root.appendingPathComponent("vendor/mediapipe")
        guard FileManager.default.fileExists(atPath: assets.appendingPathComponent("libmediapipe.dylib").path) else {
            throw XCTSkip("Run python3 scripts/fetch-tracker.py to exercise the native runtime")
        }
        return try MediaPipeTracker(libraryPath: assets.appendingPathComponent("libmediapipe.dylib").path,
                                    modelPath: assets.appendingPathComponent("hand_landmarker.task").path)
    }
    func testNativeRuntimeLoadsAndBlankFramesDoNotInventHands() throws {
        let detector = try tracker()
        let pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        try pixels.withUnsafeBufferPointer { buffer in
            XCTAssertTrue(try detector.detect(bgra: buffer.baseAddress!, width: 64, height: 64, stride: 256, time: 1).isEmpty)
            XCTAssertTrue(try detector.detect(bgra: buffer.baseAddress!, width: 64, height: 64, stride: 256, time: 1.1).isEmpty)
        }
    }
    func testRealPointingImageThroughNativeBridge() throws {
        guard let path = ProcessInfo.processInfo.environment["TONYSTARK_POINTING_IMAGE"] else {
            throw XCTSkip("Set TONYSTARK_POINTING_IMAGE for the public MediaPipe pointing_up.jpg fixture")
        }
        let hands = try detectImage(at: path)
        XCTAssertEqual(hands.count, 1)
        let hand = try XCTUnwrap(hands.first)
        XCTAssertEqual(hand.image.count, 21); XCTAssertEqual(hand.world.count, 21)
        XCTAssertEqual(SpatialHandGeometry(image: hand.image, world: hand.world).sample()?.pose, .point)
    }

    func testTwoRealHandsThroughNativeBridge() throws {
        guard let path = ProcessInfo.processInfo.environment["TONYSTARK_TWO_HAND_IMAGE"] else {
            throw XCTSkip("Set TONYSTARK_TWO_HAND_IMAGE for the public MediaPipe right_hands.jpg fixture")
        }
        let hands = try detectImage(at: path)
        XCTAssertEqual(hands.count, 2)
        let wrists = try hands.map { hand in
            XCTAssertEqual(hand.world.count, 21)
            XCTAssertEqual(hand.image.count, 21)
            return try XCTUnwrap(hand.image["wrist"])
        }
        XCTAssertEqual(wrists.count, 2)
        guard wrists.count == 2 else { return }
        XCTAssertGreaterThan(wrists[0].distance(to: wrists[1]), 0.1)
    }

    private func detectImage(at path: String) throws -> [TrackedHand] {
        let detector = try tracker()
        let nsImage = try XCTUnwrap(NSImage(contentsOfFile: path))
        let image = try XCTUnwrap(nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let width = image.width, height = image.height, stride = width * 4
        var pixels = [UInt8](repeating: 0, count: stride * height)
        return try pixels.withUnsafeMutableBytes { bytes -> [TrackedHand] in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: stride, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue))
            context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return try detector.detect(bgra: bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), width: width, height: height, stride: stride, time: 1)
        }
    }
}
