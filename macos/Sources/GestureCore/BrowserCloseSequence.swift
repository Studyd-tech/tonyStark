public enum BrowserCloseAction: Equatable {
    case tab, window
}

/// A repeat applies only to the same browser window, after a successful tab command.
public struct BrowserCloseSequence<Target: Equatable> {
    private var previousTarget: Target?
    private var previousTime: Double?
    public init() {}

    public func action(for target: Target, at time: Double) -> BrowserCloseAction {
        if previousTarget == target, let previousTime, (0...3).contains(time - previousTime) {
            return .window
        }
        return .tab
    }

    public mutating func recordSuccess(_ action: BrowserCloseAction, target: Target, at time: Double) {
        if action == .window { reset() }
        else { previousTarget = target; previousTime = time }
    }

    public mutating func reset() { previousTarget = nil; previousTime = nil }
}
