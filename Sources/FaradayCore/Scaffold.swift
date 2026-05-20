import Foundation

public struct BeaconObservation: Equatable {
    public let timestamp: Date
    public let rssi: Int

    public init(timestamp: Date, rssi: Int) {
        self.timestamp = timestamp
        self.rssi = rssi
    }
}

public enum ProximityClassification: Equatable {
    case near
    case far
    case uncertain
    case missing
}

public enum SessionState: Equatable {
    case idle
    case waitingForFar
    case active
}

public enum SessionCommand: Equatable {
    case none
    case showBeaconMissingAtStart
    case beginSession
    case endSession
    case requestLock
}

public protocol EnforcementAdapting {
    func requestLock()
}

public final class NoopEnforcementAdapter: EnforcementAdapting {
    public init() {}
    public func requestLock() {}
}

public struct FocusSessionStateMachine {
    public private(set) var state: SessionState = .idle

    public init() {}

    public mutating func start(classification: ProximityClassification) -> SessionCommand {
        switch classification {
        case .missing:
            state = .idle
            return .showBeaconMissingAtStart
        case .near, .far, .uncertain:
            state = .waitingForFar
            return .none
        }
    }

    public mutating func stop() -> SessionCommand {
        state = .idle
        return .endSession
    }

    public mutating func receive(classification: ProximityClassification) -> SessionCommand {
        switch (state, classification) {
        case (.waitingForFar, .far):
            state = .active
            return .beginSession
        case (.active, .near), (.active, .missing):
            return .requestLock
        default:
            return .none
        }
    }
}

public final class FaradayCore {
    private var sessionStateMachine: FocusSessionStateMachine
    private let enforcement: EnforcementAdapting

    public init(
        sessionStateMachine: FocusSessionStateMachine = FocusSessionStateMachine(),
        enforcement: EnforcementAdapting = NoopEnforcementAdapter()
    ) {
        self.sessionStateMachine = sessionStateMachine
        self.enforcement = enforcement
    }

    @discardableResult
    public func startSession(classification: ProximityClassification) -> SessionCommand {
        sessionStateMachine.start(classification: classification)
    }

    @discardableResult
    public func stopSession() -> SessionCommand {
        sessionStateMachine.stop()
    }

    @discardableResult
    public func handle(classification: ProximityClassification) -> SessionCommand {
        let command = sessionStateMachine.receive(classification: classification)
        if command == .requestLock {
            enforcement.requestLock()
        }
        return command
    }

    public var state: SessionState {
        sessionStateMachine.state
    }
}
