import Foundation

public struct Point3D: Equatable {
    public let x: Double, y: Double, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    public var finite: Bool { x.isFinite && y.isFinite && z.isFinite }
    public func distance(to p: Point3D) -> Double { sqrt(pow(x - p.x, 2) + pow(y - p.y, 2) + pow(z - p.z, 2)) }
}

/// Gesture shape is measured in estimated metric 3D coordinates. Screen aim
/// still comes from the current mirrored image; depth is never claimed to be
/// measured distance from the user to the display.
public struct SpatialHandGeometry {
    public let image: [String: Point]
    public let world: [String: Point3D]
    public init(image: [String: Point], world: [String: Point3D]) { self.image = image; self.world = world }

    public func sample(pinchThreshold: Double = 0.4, retainingPinch: Bool = false) -> HandSample? {
        let names = ["wrist", "indexMCP", "indexPIP", "indexDIP", "indexTip", "middleMCP", "middlePIP", "middleDIP", "middleTip",
                     "ringMCP", "ringPIP", "ringDIP", "ringTip", "littleMCP", "littlePIP", "littleDIP", "littleTip", "thumbTip"]
        guard names.allSatisfy({ world[$0]?.finite == true }),
              let tip = image["indexTip"], let wristImage = image["wrist"], let middleImage = image["middleMCP"],
              [tip, wristImage, middleImage].allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let wrist = world["wrist"]!, scale = wrist.distance(to: world["middleMCP"]!)
        guard scale > 0.01, scale < 0.3 else { return nil }
        func angle(_ a: Point3D, _ b: Point3D, _ c: Point3D) -> Double {
            let u = Point3D(a.x - b.x, a.y - b.y, a.z - b.z)
            let v = Point3D(c.x - b.x, c.y - b.y, c.z - b.z)
            let length = u.distance(to: Point3D(0, 0, 0)) * v.distance(to: Point3D(0, 0, 0))
            guard length > 1e-8 else { return 0 }
            return acos(min(1, max(-1, (u.x * v.x + u.y * v.y + u.z * v.z) / length))) * 180 / .pi
        }
        func reach(_ finger: String) -> Double {
            world[finger + "Tip"]!.distance(to: wrist) / max(0.001, world[finger + "MCP"]!.distance(to: wrist))
        }
        func extended(_ finger: String) -> Bool {
            let m = world[finger + "MCP"]!, p = world[finger + "PIP"]!, d = world[finger + "DIP"]!, t = world[finger + "Tip"]!
            // Use joint angles as well as reach; a finger pointing down the lens
            // is short in the image but retains its 3D bone alignment.
            return reach(finger) > 1.35 || (reach(finger) > 1.1 && angle(m, p, d) > 150 && angle(p, d, t) > 145)
        }
        let indexOpen = extended("index")
        let otherFingers = ["middle", "ring", "little"]
        let otherOpen = otherFingers.map(extended)
        let threshold = pinchThreshold * (retainingPinch ? 1.25 : 1)
        let thumb = world["thumbTip"]!, index = world["indexTip"]!, middle = world["middleTip"]!
        let pinch = index.distance(to: thumb) / scale < threshold && middle.distance(to: thumb) / scale < threshold &&
                    index.distance(to: wrist) / scale > 1.05 && middle.distance(to: wrist) / scale > 1.05
        let pose: Pose
        if pinch { pose = .pinch }
        else if indexOpen && otherOpen.allSatisfy({ $0 }) { pose = .palm }
        else if indexOpen && otherOpen.allSatisfy({ !$0 }) { pose = .point }
        else if indexOpen && otherOpen == [true, false, false] { pose = .twoFingers }
        else if !indexOpen && otherOpen.allSatisfy({ !$0 }) && reach("index") < 1.15 && otherFingers.allSatisfy({ reach($0) < 1.15 }) { pose = .fist }
        else { pose = .other }
        return HandSample(pose: pose, aim: tip,
                          anchor: Point((wristImage.x + middleImage.x) / 2, (wristImage.y + middleImage.y) / 2))
    }
}
