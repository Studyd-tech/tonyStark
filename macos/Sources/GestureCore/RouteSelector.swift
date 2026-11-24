import Foundation

/// Chooses one calibrated camera/display route. Overlap means ambiguity, never
/// "anything outside the laptop must be the monitor". A grab keeps its source.
public struct RouteSelector {
    public private(set) var current: String?
    private var candidate: String?
    private var candidateSince = 0.0
    public init() {}
    public mutating func reset() { self = RouteSelector() }
    public mutating func update(matches: [String], at now: Double, locked: Bool = false, onlyDisplay: Bool = false) -> String? {
        if locked { return current }
        let unique = Set(matches)
        guard unique.count == 1, let match = unique.first else {
            current = nil; candidate = nil
            return nil
        }
        if candidate != match { candidate = match; candidateSince = now }
        if current != match {
            current = nil
            if onlyDisplay || now - candidateSince >= 0.3 { current = match }
        }
        return current
    }
}
