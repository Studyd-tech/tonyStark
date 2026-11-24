/// Recognizes transitions between pairs of open palms and fists.
/// Feed only frames from one camera. The order of detections can change between frames.
public struct TwoHandGesture {
    public enum Command: Equatable { case missionControl, closeTab }

    public private(set) var readyCommand: Command?
    private var lastPairAt: Double?
    private var candidate: Pose?
    private var candidateSince = 0.0
    private var armedAt = 0.0
    private var consumedPose: Pose?

    public init() {}

    public func suppressesSingleHand(at now: Double) -> Bool {
        lastPairAt.map { now - $0 <= 0.3 } ?? false
    }

    public mutating func update(_ poses: [Pose?], at now: Double) -> Command? {
        let trackingPair = suppressesSingleHand(at: now)
        if !trackingPair { consumedPose = nil }
        if !trackingPair || poses.count != 2 {
            candidate = nil
            readyCommand = nil
        }
        if now - armedAt > 1.5 { readyCommand = nil }
        guard poses.count == 2 else { return nil }
        lastPairAt = now

        let pose = poses[0] == poses[1] ? poses[0] : nil
        if pose != candidate {
            candidate = pose
            candidateSince = now
        }
        guard let pose, pose == .fist || pose == .palm, pose != consumedPose else { return nil }

        let dwell = now - candidateSince
        let startingCommand: Command = pose == .fist ? .missionControl : .closeTab
        if let readyCommand, readyCommand != startingCommand, dwell >= 0.18 {
            self.readyCommand = nil
            // A command's ending pose must not arm the inverse command by itself.
            consumedPose = pose
            return readyCommand
        }
        if dwell >= 0.22 {
            readyCommand = startingCommand
            armedAt = now
            consumedPose = nil
        }
        return nil
    }
}
