import Foundation
import CoreVideo
import CMediaPipe
import GestureCore

public struct TrackedHand {
    public let image: [String: Point]
    public let world: [String: Point3D]
}

public final class MediaPipeTracker {
    private let handle: OpaquePointer
    public static let jointNames = ["wrist", "thumbCMC", "thumbMP", "thumbIP", "thumbTip",
        "indexMCP", "indexPIP", "indexDIP", "indexTip", "middleMCP", "middlePIP", "middleDIP", "middleTip",
        "ringMCP", "ringPIP", "ringDIP", "ringTip", "littleMCP", "littlePIP", "littleDIP", "littleTip"]

    public init(libraryPath: String, modelPath: String) throws {
        var error = [CChar](repeating: 0, count: 2048)
        guard let handle = ts_hand_create(libraryPath, modelPath, &error, error.count) else {
            throw NSError(domain: "HandTracking", code: 1, userInfo: [NSLocalizedDescriptionKey: String(cString: error)])
        }
        self.handle = handle
    }
    deinit { ts_hand_close(handle) }

    public func detect(bgra: UnsafePointer<UInt8>, width: Int, height: Int, stride: Int, time: Double) throws -> [TrackedHand] {
        var result = TSHandResult()
        var error = [CChar](repeating: 0, count: 2048)
        let status = ts_hand_detect(handle, bgra, Int32(width), Int32(height), Int32(stride), Int64(time * 1000), &result, &error, error.count)
        guard status == 0 else {
            throw NSError(domain: "HandTracking", code: Int(status), userInfo: [NSLocalizedDescriptionKey: String(cString: error)])
        }
        let hands = withUnsafeBytes(of: result.hands) { Array($0.bindMemory(to: TSHand.self).prefix(Int(result.count))) }
        return hands.map(Self.convert)
    }

    private static func convert(_ hand: TSHand) -> TrackedHand {
        let image = withUnsafeBytes(of: hand.image) { Array($0.bindMemory(to: TSJoint.self)) }
        let world = withUnsafeBytes(of: hand.world) { Array($0.bindMemory(to: TSJoint.self)) }
        var imageJoints: [String: Point] = [:], worldJoints: [String: Point3D] = [:]
        for i in 0..<21 {
            let p = image[i], w = world[i]
            if hand.has_image != 0, p.x.isFinite, p.y.isFinite, (-0.1...1.1).contains(p.x), (-0.1...1.1).contains(p.y) {
                imageJoints[jointNames[i]] = Point(1 - Double(p.x), Double(p.y))
            }
            if hand.has_world != 0, w.x.isFinite, w.y.isFinite, w.z.isFinite {
                worldJoints[jointNames[i]] = Point3D(Double(w.x), Double(w.y), Double(w.z))
            }
        }
        return TrackedHand(image: imageJoints, world: worldJoints)
    }

    public func detect(pixelBuffer: CVPixelBuffer, time: Double) throws -> [TrackedHand] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              let bytes = CVPixelBufferGetBaseAddress(pixelBuffer) else { return [] }
        return try detect(bgra: bytes.assumingMemoryBound(to: UInt8.self), width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer), stride: CVPixelBufferGetBytesPerRow(pixelBuffer), time: time)
    }
}
