/// Holds a target during hand commands after two seconds of steady aiming.
/// Coordinates are desktop points after calibration and cursor filtering.
public struct CursorHold {
    public var isLocked: Bool { lockedPoint != nil }
    private var lockedPoint: Point?
    private var steadyAnchor: Point?
    private var steadySince: Double?
    private var resumeSince: Double?
    private var lastUpdate: Double?

    public init() {}

    public mutating func reset() { self = CursorHold() }

    /// A pose transition or missing frame breaks dwell, but preserves a held target.
    public mutating func suspend() {
        steadyAnchor = nil
        steadySince = nil
        resumeSince = nil
        lastUpdate = nil
    }

    public mutating func update(_ point: Point, at time: Double) -> Point {
        if let previous = lastUpdate, time - previous > 0.18 || time < previous {
            suspend()
        }
        lastUpdate = time
        if let locked = lockedPoint {
            // Opening a palm can briefly still look like pointing. Require both
            // meaningful movement and continuous pointing before following again.
            if point.distance(to: locked) > 24 {
                if resumeSince == nil { resumeSince = time }
                if let started = resumeSince, time - started >= 0.3 {
                    lockedPoint = nil
                    resumeSince = nil
                    steadyAnchor = point
                    steadySince = time
                    return point
                }
            } else {
                resumeSince = nil
            }
            return locked
        }
        if let anchor = steadyAnchor, point.distance(to: anchor) <= 12 {
            if let started = steadySince, time - started >= 2 {
                lockedPoint = point
                steadyAnchor = nil
                steadySince = nil
            }
        } else {
            steadyAnchor = point
            steadySince = time
        }
        return point
    }
}
