import Foundation

public struct CalibrationFrame {
    public let time: Double
    public let hand: HandSample?
    public init(time: Double, hand: HandSample?) { self.time = time; self.hand = hand }
}

public enum CaptureProblem: Error, Equatable {
    case handMissing, pointRequired, keepStill
}

public enum CalibrationCapture {
    /// Only the end of the countdown matters, so the user has time to press
    /// Space and position their hand. Missing detections cannot count as a hold.
    public static func assess(_ frames: [CalibrationFrame], at now: Double) -> Result<Point, CaptureProblem> {
        let recent = frames.filter { $0.time <= now && now - $0.time <= 0.6 }
        guard recent.count >= 8, let last = recent.last, now - last.time < 0.15,
              recent.allSatisfy({ $0.hand != nil }) else { return .failure(.handMissing) }
        guard recent.allSatisfy({ $0.hand?.pose == .point }) else { return .failure(.pointRequired) }
        let points = recent.compactMap { $0.hand?.aim }
        let median = Point(points.map(\.x).sorted()[points.count / 2], points.map(\.y).sorted()[points.count / 2])
        guard points.allSatisfy({ $0.distance(to: median) < 0.045 }) else { return .failure(.keepStill) }
        return .success(median)
    }
}
