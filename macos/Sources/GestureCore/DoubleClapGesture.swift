/// A palm center and size in aspect-corrected camera coordinates.
/// The two hands' independently centered world landmarks cannot measure their gap.
public struct ClapHand {
    public let center: Point
    public let size: Double
    public let pose: Pose?

    public init(center: Point, size: Double, pose: Pose? = .palm) {
        self.center = center; self.size = size; self.pose = pose
    }

    public init?(image: [String: Point], pose: Pose?, aspectRatio: Double) {
        let names = ["wrist", "indexMCP", "middleMCP", "littleMCP"]
        guard aspectRatio.isFinite, aspectRatio > 0,
              names.allSatisfy({ image[$0]?.x.isFinite == true && image[$0]?.y.isFinite == true }) else { return nil }
        let points = names.map { Point(image[$0]!.x * aspectRatio, image[$0]!.y) }
        let size = points[0].distance(to: points[2])
        guard size > 0.02 else { return nil }
        self.init(center: Point(points.map(\.x).reduce(0, +) / 4,
                                points.map(\.y).reduce(0, +) / 4), size: size, pose: pose)
    }
}

/// Recognizes two visible claps, without microphone access. Each contact must
/// follow a fast inward motion from separated hands; missing detections never count.
public struct DoubleClapGesture {
    private enum Phase {
        case waiting, spread(gap: Double, since: Double), closing(gap: Double, since: Double), touching
    }
    private var phase = Phase.waiting
    private var lastPairAt: Double?
    private var firstClapAt: Double?
    private var cooldownUntil = 0.0
    public var waitingForSecondClap: Bool { firstClapAt != nil }
    public var inProgress: Bool {
        if firstClapAt != nil { return true }
        if case .closing = phase { return true }
        return false
    }

    public init() {}
    public mutating func reset() { self = DoubleClapGesture() }
    public func suppressesOtherGestures(at now: Double) -> Bool { inProgress || now < cooldownUntil }

    private mutating func clearSequence() {
        phase = .waiting
        firstClapAt = nil
    }

    public mutating func update(_ hands: [ClapHand], at now: Double) -> Bool {
        if let lastPairAt, now < lastPairAt || now - lastPairAt > 0.2 { clearSequence() }
        if let firstClapAt, now - firstClapAt > 1.2 { clearSequence() }
        guard now >= cooldownUntil, hands.count == 2,
              hands.allSatisfy({ $0.size.isFinite && $0.size > 0.02 &&
                  $0.center.x.isFinite && $0.center.y.isFinite }) else { return false }
        lastPairAt = now
        let gap = hands[0].center.distance(to: hands[1].center) / max(hands[0].size, hands[1].size)
        // Edge-on palms may be uncertain, but a definite point, fist, or pinch
        // must not start a clap. Once approaching, tolerate shape changes at contact.
        let openHands = hands.allSatisfy { $0.pose == nil || $0.pose == .palm || $0.pose == .other }
        switch phase {
        case .waiting:
            if gap >= 2.2 && openHands { phase = .spread(gap: gap, since: now) }
        case .spread(let start, let since):
            if start - gap >= 0.45 && now - since <= 0.8 {
                phase = .closing(gap: start, since: since)
                // Also evaluate contact in this frame: a fast clap may jump
                // directly from spread to touching at the camera's frame rate.
                return contact(gap: gap, start: start, since: since, at: now)
            }
            if !openHands { clearSequence(); break }
            if gap >= start - 0.2 || now - since > 0.8 {
                phase = gap >= 2.2 ? .spread(gap: gap, since: now) : .waiting
            }
        case .closing(let start, let since):
            if now - since > 0.8 { clearSequence() }
            else if gap >= start { phase = .spread(gap: gap, since: now) }
            else { return contact(gap: gap, start: start, since: since, at: now) }
        case .touching:
            if gap >= 2.2 && openHands { phase = .spread(gap: gap, since: now) }
        }
        return false
    }

    private mutating func contact(gap: Double, start: Double, since: Double, at now: Double) -> Bool {
        guard gap <= 0.9, start - gap >= 0.9, now - since >= 0.05 else { return false }
        if let firstClapAt, now - firstClapAt <= 1.2 {
            clearSequence()
            cooldownUntil = now + 2
            return true
        }
        firstClapAt = now
        phase = .touching
        return false
    }
}
