import Foundation

public struct BeaconObservation: Equatable {
    public let timestamp: Date
    public let rssi: Int

    public init(timestamp: Date, rssi: Int) {
        self.timestamp = timestamp
        self.rssi = rssi
    }
}

public struct BeaconIdentifier: Equatable, Hashable {
    public let uuid: UUID
    public let major: Int
    public let minor: Int

    public init(uuid: UUID, major: Int, minor: Int) {
        self.uuid = uuid
        self.major = major
        self.minor = minor
    }
}

public struct BeaconAdvertisement: Equatable {
    public let identifier: BeaconIdentifier
    public let timestamp: Date
    public let rssi: Int

    public init(identifier: BeaconIdentifier, timestamp: Date, rssi: Int) {
        self.identifier = identifier
        self.timestamp = timestamp
        self.rssi = rssi
    }
}

public final class BeaconAllowlistScanner {
    private let allowlist: Set<BeaconIdentifier>
    public private(set) var isScanning = false
    public private(set) var observations: [BeaconObservation] = []

    public init(allowlist: [BeaconIdentifier]) {
        self.allowlist = Set(allowlist)
    }

    public func start() {
        isScanning = true
    }

    public func stop() {
        isScanning = false
    }

    public func ingest(_ advertisement: BeaconAdvertisement) {
        guard isScanning else { return }
        guard allowlist.contains(advertisement.identifier) else { return }

        observations.append(
            BeaconObservation(timestamp: advertisement.timestamp, rssi: advertisement.rssi)
        )
    }
}

public enum ProximityClassification: Equatable {
    case near
    case far
    case uncertain
    case missing
}

public struct RSSIClassificationTraceEntry: Equatable {
    public let timestamp: Date
    public let classification: ProximityClassification

    public init(timestamp: Date, classification: ProximityClassification) {
        self.timestamp = timestamp
        self.classification = classification
    }
}

public final class RSSIClassificationTracer {
    public private(set) var entries: [RSSIClassificationTraceEntry] = []
    private let maxEntries: Int

    public init(maxEntries: Int = 500) {
        self.maxEntries = max(1, maxEntries)
    }

    public func record(_ classification: ProximityClassification, at timestamp: Date = Date()) {
        if entries.last?.classification == classification {
            return
        }

        entries.append(RSSIClassificationTraceEntry(timestamp: timestamp, classification: classification))

        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }
}

public enum SessionState: Equatable {
    case idle
    case waitingForFar
    case active
}

public enum SessionCommand: Equatable {
    case none
    case showBeaconMissingAtStart
    case showBeaconMustBeNearAtStart
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
        case .near:
            state = .waitingForFar
            return .none
        case .far, .uncertain:
            state = .idle
            return .showBeaconMustBeNearAtStart
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
