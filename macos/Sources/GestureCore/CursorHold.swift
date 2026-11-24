/// Holds a target during hand commands after two seconds of steady aiming.
/// Coordinates are desktop points after calibration and cursor filtering.
public struct CursorHold {
    public var isLocked: Bool { lockedPoint != nil }
    private var lockedPoint: Point?
    private var steadyAnchor: Point?
    private var steadySince: Double?
    private var leftPointing = false
    private var nonPointingPose: Pose?
    private var nonPointingSince: Double?
    private var pointingSince: Double?
    private var lastUpdate: Double?

    public init() {}

    public mutating func reset() { self = CursorHold() }

    /// Every non-pointing camera sample must be reported, including missing hands.
    /// Only a confirmed command pose followed by a fresh point can release a hold.
    public mutating func observePose(_ pose: Pose?, at time: Double) {
        if let previous = lastUpdate, time - previous > 0.18 || time < previous {
            breakDwell()
        }
        lastUpdate = time
        if pose == .point {
            nonPointingPose = nil
            nonPointingSince = nil
            if pointingSince == nil { pointingSince = time }
        } else {
            steadyAnchor = nil
            steadySince = nil
            pointingSince = nil
            if let pose, pose != .other {
                if nonPointingPose != pose {
                    nonPointingPose = pose
                    nonPointingSince = time
                }
                if isLocked, let started = nonPointingSince, time - started >= 0.18 {
                    leftPointing = true
                }
            } else {
                nonPointingPose = nil
                nonPointingSince = nil
            }
        }
    }

    private mutating func breakDwell() {
        steadyAnchor = nil
        steadySince = nil
        nonPointingPose = nil
        nonPointingSince = nil
        pointingSince = nil
    }

    /// Called only for pointing poses, with the proposed cursor position.
    public mutating func update(_ point: Point, at time: Double) -> Point {
        observePose(.point, at: time)
        if let locked = lockedPoint {
            // Movement alone cannot release the lock: unfolding a palm moves the
            // fingertip while it may still be classified as the original point.
            if leftPointing, let started = pointingSince, time - started >= 0.4 {
                lockedPoint = nil
                leftPointing = false
                steadyAnchor = point
                steadySince = time
                return point
            }
            return locked
        }
        if let anchor = steadyAnchor, point.distance(to: anchor) <= 12 {
            if let started = steadySince, time - started >= 2 {
                lockedPoint = point
                leftPointing = false
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
