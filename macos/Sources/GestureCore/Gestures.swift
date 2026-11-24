import Foundation

public struct Point: Codable, Equatable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public func distance(to p: Point) -> Double { hypot(x - p.x, y - p.y) }
}

public enum Pose: String {
    case point, fist, palm, pinch, other
    case twoFingers = "two fingers"
}

public struct HandSample {
    public let pose: Pose
    public let aim: Point
    public let anchor: Point
    public init(pose: Pose, aim: Point, anchor: Point) {
        self.pose = pose; self.aim = aim; self.anchor = anchor
    }
}

public enum GestureAction: Equatable {
    case armed, disarmed, cursor(Point), click, missionControl, grab(Point), drag(Point), release
    case selectWindow, minimizeSelectedWindow
    case scrollStarted, scroll(Int32), scrollEnded
}

/// Uses monotonic seconds. Commands require stable poses; no raw camera frame causes a click.
public struct GestureMachine {
    public private(set) var armed = false
    public private(set) var dragging = false
    public var scrolling: Bool { scrollAnchorY != nil }
    private var scrollAnchorY: Double?
    private var candidate: Pose?
    private var candidateSince = 0.0
    private var lastSeen: Double?
    private var pointLostAt: Double?
    private var lastIntent = 0.0
    private var fistPrimedAt: Double?
    private var palmOpenedAt: Double?
    private var fistConsumed = false
    private var lastPointingAt: Double?
    private var palmSelectedWindow = false
    private var missionCooldownUntil = 0.0
    private static let clickWindow = 0.65

    public init() {}

    public mutating func reset() -> [GestureAction] {
        var actions: [GestureAction] = []
        if dragging { actions.append(.release) }
        if scrolling { actions.append(.scrollEnded) }
        if armed { actions.append(.disarmed) }
        self = GestureMachine()
        return actions
    }

    public mutating func expire(at now: Double) -> [GestureAction] {
        if let lastSeen, now - lastSeen > 0.4 { return reset() }
        if armed && !dragging && now - lastIntent > 10 { return reset() }
        return []
    }

    public mutating func update(_ hand: HandSample?, at now: Double) -> [GestureAction] {
        guard let hand else {
            // A brief miss pauses an unarmed point hold. All command dwells still
            // break immediately on occlusion, and the tracking timeout still applies.
            if !armed, candidate == .point, let lastSeen, now - lastSeen <= 0.18 {
                pointLostAt = lastSeen
            } else {
                candidate = nil
                pointLostAt = nil
            }
            fistPrimedAt = nil
            palmOpenedAt = nil
            lastPointingAt = nil
            palmSelectedWindow = false
            var actions: [GestureAction] = []
            if scrolling {
                scrollAnchorY = nil
                actions.append(.scrollEnded)
            }
            return actions + expire(at: now)
        }
        var actions = expire(at: now)
        if let pointLostAt {
            if hand.pose == .point && now - pointLostAt <= 0.18 {
                candidateSince += now - pointLostAt
            } else {
                candidate = nil
            }
            self.pointLostAt = nil
        }
        lastSeen = now
        if candidate != hand.pose { candidate = hand.pose; candidateSince = now }
        if hand.pose != .fist { fistConsumed = false }
        if now - lastIntent > 1 { palmSelectedWindow = false }
        let dwell = now - candidateSince

        guard armed else {
            if hand.pose == .point && dwell >= 0.75 {
                armed = true; lastIntent = now
                lastPointingAt = now
                actions.append(.armed)
                actions.append(.cursor(hand.aim))
            }
            return actions
        }

        if dragging {
            // Release never waits on a coordinate update: the hand can relax without
            // pulling the window in the final frames of opening the pinch.
            if hand.pose == .pinch {
                lastIntent = now
                actions.append(.drag(hand.anchor))
            } else if dwell >= 0.14 {
                dragging = false; fistPrimedAt = nil
                actions.append(.release)
            }
            return actions
        }

        if let anchorY = scrollAnchorY {
            if hand.pose == .twoFingers {
                lastIntent = now
                let movement = hand.anchor.y - anchorY
                // Accumulate slow movement while ignoring small landmark jitter.
                // Positive wheel deltas move the content down with the hand.
                if abs(movement) >= 0.006 {
                    let pixels = Int32(min(80, max(-80, movement * 1700)).rounded())
                    actions.append(.scroll(pixels))
                    scrollAnchorY = hand.anchor.y
                }
            } else if dwell >= 0.14 {
                scrollAnchorY = nil
                actions.append(.scrollEnded)
            }
            return actions
        }

        switch hand.pose {
        case .point:
            // Closing a palm can briefly look like pointing as the fingers fold.
            // Keep the selected window until the user clearly starts aiming again.
            if palmSelectedWindow && dwell < 0.16 { break }
            lastIntent = now; fistPrimedAt = nil; palmOpenedAt = nil
            lastPointingAt = now
            palmSelectedWindow = false
            actions.append(.cursor(hand.aim))
        case .pinch:
            if dwell >= 0.18 {
                fistPrimedAt = nil; palmOpenedAt = nil
                lastPointingAt = nil
                palmSelectedWindow = false
                dragging = true; lastIntent = now
                actions.append(.grab(hand.anchor))
            }
        case .twoFingers:
            if dwell >= 0.24 {
                fistPrimedAt = nil; palmOpenedAt = nil
                lastPointingAt = nil
                palmSelectedWindow = false
                lastIntent = now
                scrollAnchorY = hand.anchor.y
                actions.append(.scrollStarted)
            }
        case .fist:
            if dwell >= 0.22 {
                lastPointingAt = nil
                if palmSelectedWindow {
                    palmSelectedWindow = false
                    fistConsumed = true
                    lastIntent = now
                    actions.append(.minimizeSelectedWindow)
                    break
                }
            }
            if let opened = palmOpenedAt, candidateSince - opened <= Self.clickWindow {
                // A fist started before the deadline can finish its dwell after it.
                if dwell >= 0.22 {
                    palmOpenedAt = nil
                    fistConsumed = true
                    lastIntent = now
                    actions.append(.click)
                }
            } else {
                palmOpenedAt = nil
                if !fistConsumed && dwell >= 0.22 {
                    fistPrimedAt = now; lastIntent = now
                }
            }
        case .palm:
            guard dwell >= 0.18 else { break }
            if let pointed = lastPointingAt, candidateSince - pointed <= 0.65 {
                lastPointingAt = nil
                fistPrimedAt = nil
                palmOpenedAt = nil
                palmSelectedWindow = true
                lastIntent = now
                actions.append(.selectWindow)
            } else if palmSelectedWindow {
                lastIntent = now
            } else if let opened = palmOpenedAt {
                if now - opened >= Self.clickWindow {
                    palmOpenedAt = nil
                    if now >= missionCooldownUntil {
                        actions.append(.missionControl)
                        missionCooldownUntil = now + 2
                        lastIntent = now
                    }
                }
            } else if let primed = fistPrimedAt, now - primed <= 1.5 {
                palmOpenedAt = now
                fistPrimedAt = nil; lastIntent = now
            }
        case .other:
            // Allow the short transition between fist and palm, but don't carry a
            // primed command through an unrelated gesture indefinitely.
            if let primed = fistPrimedAt, now - primed > 1.5 { fistPrimedAt = nil }
            if let opened = palmOpenedAt, now - opened > Self.clickWindow { palmOpenedAt = nil }
        }
        return actions
    }
}

public struct HandGeometry {
    public let joints: [String: Point]
    private let aspectRatio: Double
    public init(joints: [String: Point], aspectRatio: Double = 1) {
        self.joints = joints; self.aspectRatio = aspectRatio
    }

    public func sample(pinchThreshold: Double = 0.4, retainingPinch: Bool = false) -> HandSample? {
        let required = ["wrist", "indexTip", "indexMCP", "middleMCP"]
        guard required.allSatisfy({ joints[$0] != nil }) else { return nil }
        let wrist = joints["wrist"]!
        func distance(_ a: Point, _ b: Point) -> Double {
            hypot((a.x - b.x) * aspectRatio, a.y - b.y)
        }
        let scale = distance(wrist, joints["middleMCP"]!)
        guard scale > 0.025 else { return nil }
        func reach(_ finger: String) -> Double? {
            guard let tip = joints[finger + "Tip"], let base = joints[finger + "MCP"] else { return nil }
            return distance(tip, wrist) / max(0.001, distance(base, wrist))
        }
        let indexReach = reach("index")!
        let otherReaches = ["middle", "ring", "little"].compactMap(reach)
        let threshold = pinchThreshold * (retainingPinch ? 1.25 : 1)
        // In a fist the folded fingertips can also sit next to the thumb. A grab
        // requires the pinched tips to be lifted away from the palm/wrist.
        var pinch = false
        if let thumb = joints["thumbTip"], let middleTip = joints["middleTip"] {
            let liftedTips = distance(joints["indexTip"]!, wrist) / scale > 1.1 && distance(middleTip, wrist) / scale > 1.1
            pinch = liftedTips && distance(thumb, joints["indexTip"]!) / scale < threshold && distance(thumb, middleTip) / scale < threshold
        }
        // Toward-camera pointing foreshortens the index finger. Compare its
        // extension with the folded fingers instead of requiring a long silhouette.
        // Two folded fingers must still be visible; a hidden pinky alone no longer
        // turns a usable pointing hand into "no hand".
        let othersFolded = otherReaches.count >= 2 && otherReaches.allSatisfy { $0 < 1.5 }
        let medianOther = otherReaches.sorted().dropFirst(otherReaches.count / 2).first ?? indexReach
        let pointing = othersFolded && (indexReach > 1.5 || (indexReach > 1.08 && indexReach - medianOther > 0.18))
        let pose: Pose
        if pinch { pose = .pinch }
        else if indexReach > 1.5 && otherReaches.count == 3 && otherReaches.allSatisfy({ $0 > 1.5 }) { pose = .palm }
        else if pointing { pose = .point }
        else if otherReaches.count >= 2 && indexReach < 1.5 && otherReaches.allSatisfy({ $0 < 1.5 }) { pose = .fist }
        else { pose = .other }
        let middle = joints["middleMCP"]!
        return HandSample(pose: pose, aim: joints["indexTip"]!,
                          anchor: Point((wrist.x + middle.x) / 2, (wrist.y + middle.y) / 2))
    }
}
