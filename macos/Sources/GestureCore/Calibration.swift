import Foundation

/// A four-point projective mapping from camera image coordinates to normalized
/// desktop coordinates. This is calibrated 2D aiming, not measured camera depth.
public struct Calibration: Codable {
    private let h: [Double]

    public init?(camera: [Point], desktop: [Point]) {
        guard camera.count == 4, desktop.count == 4,
              camera.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              desktop.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        // Reject folded/very small quadrilaterals. Order: TL, TR, BR, BL.
        func convexArea(_ points: [Point]) -> Bool {
            var signs: [Double] = []
            var area = 0.0
            for i in 0..<4 {
                let a = points[i], b = points[(i + 1) % 4], c = points[(i + 2) % 4]
                signs.append((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x))
                area += a.x * b.y - b.x * a.y
            }
            return abs(area) > 0.012 && (signs.allSatisfy { $0 > 0.0001 } || signs.allSatisfy { $0 < -0.0001 })
        }
        guard convexArea(camera), convexArea(desktop) else { return nil }
        var rows: [[Double]] = []
        for (p, q) in zip(camera, desktop) {
            rows.append([p.x, p.y, 1, 0, 0, 0, -q.x * p.x, -q.x * p.y, q.x])
            rows.append([0, 0, 0, p.x, p.y, 1, -q.y * p.x, -q.y * p.y, q.y])
        }
        for col in 0..<8 {
            let pivot = (col..<8).max { abs(rows[$0][col]) < abs(rows[$1][col]) }!
            guard abs(rows[pivot][col]) > 1e-8 else { return nil }
            rows.swapAt(col, pivot)
            let divisor = rows[col][col]
            for j in col...8 { rows[col][j] /= divisor }
            for i in 0..<8 where i != col {
                let factor = rows[i][col]
                for j in col...8 { rows[i][j] -= factor * rows[col][j] }
            }
        }
        h = rows.map { $0[8] }
        // A vanishing line inside the working area would make the cursor jump.
        let denominators = camera.map { h[6] * $0.x + h[7] * $0.y + 1 }
        guard denominators.allSatisfy({ $0 > 0.05 }) || denominators.allSatisfy({ $0 < -0.05 }) else { return nil }
    }

    public func map(_ p: Point) -> Point? {
        guard h.count == 8 else { return nil }
        let d = h[6] * p.x + h[7] * p.y + 1
        guard abs(d) > 0.05 else { return nil }
        let x = (h[0] * p.x + h[1] * p.y + h[2]) / d
        let y = (h[3] * p.x + h[4] * p.y + h[5]) / d
        guard x.isFinite, y.isFinite else { return nil }
        return Point(x, y)
    }
}

public struct CursorFilter {
    private var previous: Point?
    private var previousTime = 0.0
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func update(_ point: Point, at time: Double) -> Point {
        guard let old = previous else { previous = point; previousTime = time; return point }
        let dt = min(0.1, max(0.001, time - previousTime))
        let alpha = 1 - exp(-dt / 0.065)
        let filtered = Point(old.x + alpha * (point.x - old.x), old.y + alpha * (point.y - old.y))
        previous = filtered; previousTime = time
        return filtered
    }
}
