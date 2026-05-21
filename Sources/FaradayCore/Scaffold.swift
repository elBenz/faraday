import Foundation

public struct BeaconObservation: Equatable {
    public let timestamp: Date
    public let rssi: Int

    public init(timestamp: Date, rssi: Int) {
        self.timestamp = timestamp
        self.rssi = rssi
    }
}

public struct BeaconIdentifier: Equatable, Hashable, Codable {
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
    public private(set) var firstValidatedBeacon: BeaconAdvertisement?

    public init(allowlist: [BeaconIdentifier]) {
        self.allowlist = Set(allowlist)
    }

    public func start() {
        isScanning = true
        firstValidatedBeacon = nil
    }

    public func stop() {
        isScanning = false
    }

    public func ingest(_ advertisement: BeaconAdvertisement) {
        guard isScanning else { return }
        guard allowlist.contains(advertisement.identifier) else { return }

        if firstValidatedBeacon == nil {
            firstValidatedBeacon = advertisement
        }

        observations.append(
            BeaconObservation(timestamp: advertisement.timestamp, rssi: advertisement.rssi)
        )
    }
}

public enum ProximityClassification: Equatable, Codable {
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

public enum SessionState: Equatable, Codable {
    case idle
    case waitingForFar
    case active
    case unsafe
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
    private let missingBeaconGracePeriod: TimeInterval
    private var activeMissingSince: Date?
    private var lastNonMissingActiveClassification: ProximityClassification?

    public init(missingBeaconGracePeriod: TimeInterval = 10) {
        self.missingBeaconGracePeriod = max(0, missingBeaconGracePeriod)
    }

    public mutating func start(classification: ProximityClassification) -> SessionCommand {
        activeMissingSince = nil
        lastNonMissingActiveClassification = nil

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
        activeMissingSince = nil
        lastNonMissingActiveClassification = nil
        return .endSession
    }

    public mutating func receive(classification: ProximityClassification, at timestamp: Date = Date()) -> SessionCommand {
        switch (state, classification) {
        case (.waitingForFar, .far):
            state = .active
            activeMissingSince = nil
            lastNonMissingActiveClassification = .far
            return .beginSession
        case (.active, .near):
            state = .unsafe
            activeMissingSince = nil
            lastNonMissingActiveClassification = .near
            return .requestLock
        case (.active, .uncertain):
            activeMissingSince = nil
            lastNonMissingActiveClassification = .uncertain
            return .none
        case (.active, .far):
            activeMissingSince = nil
            lastNonMissingActiveClassification = .far
            return .none
        case (.active, .missing):
            let lastClassification = lastNonMissingActiveClassification
            if lastClassification == .far {
                if activeMissingSince == nil {
                    activeMissingSince = timestamp
                    return .none
                }

                if let activeMissingSince, timestamp.timeIntervalSince(activeMissingSince) >= missingBeaconGracePeriod {
                    state = .unsafe
                    return .requestLock
                }

                return .none
            }

            state = .unsafe
            return .requestLock
        case (.unsafe, .far):
            state = .active
            activeMissingSince = nil
            lastNonMissingActiveClassification = .far
            return .none
        default:
            return .none
        }
    }
}

public struct FaradaySettings: Equatable, Codable {
    public let beacon: BeaconIdentifier?
    public let nearThresholdRSSI: Int
    public let farThresholdRSSI: Int

    public init(beacon: BeaconIdentifier?, nearThresholdRSSI: Int, farThresholdRSSI: Int) {
        self.beacon = beacon
        self.nearThresholdRSSI = nearThresholdRSSI
        self.farThresholdRSSI = farThresholdRSSI
    }
}

public struct FaradayCalibration: Equatable, Codable {
    public let deskRSSI: [Int]
    public let doorwayRSSI: [Int]
    public let targetRoomRSSI: [Int]

    public init(deskRSSI: [Int] = [], doorwayRSSI: [Int] = [], targetRoomRSSI: [Int] = []) {
        self.deskRSSI = deskRSSI
        self.doorwayRSSI = doorwayRSSI
        self.targetRoomRSSI = targetRoomRSSI
    }
}

public enum FaradayEventKind: Equatable, Codable {
    case sessionWaitingForFar
    case sessionBegan
    case sessionEnded
    case missingBeacon
    case violation
    case lockRequested
    case emergencyStarted
    case emergencyExtended
    case emergencyRefused
    case emergencyExpired
}

public struct FaradayEvent: Equatable, Codable {
    public let timestamp: Date
    public let kind: FaradayEventKind

    public init(timestamp: Date, kind: FaradayEventKind) {
        self.timestamp = timestamp
        self.kind = kind
    }
}

public struct FaradayStatus: Equatable, Codable {
    public let sessionState: SessionState
    public let lastClassification: ProximityClassification?

    public init(sessionState: SessionState, lastClassification: ProximityClassification?) {
        self.sessionState = sessionState
        self.lastClassification = lastClassification
    }
}

public protocol FaradayPersisting {
    func loadSettings() -> FaradaySettings?
    func saveSettings(_ settings: FaradaySettings)
    func loadCalibration() -> FaradayCalibration?
    func saveCalibration(_ calibration: FaradayCalibration)
    func appendEvent(_ event: FaradayEvent)
    func loadEvents() -> [FaradayEvent]
    func saveStatus(_ status: FaradayStatus)
    func loadStatus() -> FaradayStatus?
}

public final class InMemoryFaradayPersistence: FaradayPersisting {
    public private(set) var settings: FaradaySettings?
    public private(set) var calibration: FaradayCalibration?
    public private(set) var events: [FaradayEvent] = []
    public private(set) var status: FaradayStatus?

    public init() {}

    public func loadSettings() -> FaradaySettings? { settings }
    public func saveSettings(_ settings: FaradaySettings) { self.settings = settings }

    public func loadCalibration() -> FaradayCalibration? { calibration }
    public func saveCalibration(_ calibration: FaradayCalibration) { self.calibration = calibration }

    public func appendEvent(_ event: FaradayEvent) { events.append(event) }
    public func loadEvents() -> [FaradayEvent] { events }

    public func saveStatus(_ status: FaradayStatus) { self.status = status }
    public func loadStatus() -> FaradayStatus? { status }
}

public final class JSONFaradayPersistence: FaradayPersisting {
    private let settingsURL: URL
    private let calibrationURL: URL
    private let eventsURL: URL
    private let statusURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseDirectoryURL: URL, fileManager: FileManager = .default) {
        settingsURL = baseDirectoryURL.appendingPathComponent("settings.json")
        calibrationURL = baseDirectoryURL.appendingPathComponent("calibration.json")
        eventsURL = baseDirectoryURL.appendingPathComponent("events.json")
        statusURL = baseDirectoryURL.appendingPathComponent("status.json")

        try? fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }

    public func loadSettings() -> FaradaySettings? {
        decode(FaradaySettings.self, from: settingsURL)
    }

    public func saveSettings(_ settings: FaradaySettings) {
        encode(settings, to: settingsURL)
    }

    public func loadCalibration() -> FaradayCalibration? {
        decode(FaradayCalibration.self, from: calibrationURL)
    }

    public func saveCalibration(_ calibration: FaradayCalibration) {
        encode(calibration, to: calibrationURL)
    }

    public func appendEvent(_ event: FaradayEvent) {
        var events = loadEvents()
        events.append(event)
        encode(events, to: eventsURL)
    }

    public func loadEvents() -> [FaradayEvent] {
        decode([FaradayEvent].self, from: eventsURL) ?? []
    }

    public func saveStatus(_ status: FaradayStatus) {
        encode(status, to: statusURL)
    }

    public func loadStatus() -> FaradayStatus? {
        decode(FaradayStatus.self, from: statusURL)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

public final class FaradayCore {
    private var sessionStateMachine: FocusSessionStateMachine
    private let enforcement: EnforcementAdapting
    private let persistence: FaradayPersisting
    private var lastClassification: ProximityClassification?

    public init(
        sessionStateMachine: FocusSessionStateMachine = FocusSessionStateMachine(),
        enforcement: EnforcementAdapting = NoopEnforcementAdapter(),
        persistence: FaradayPersisting = InMemoryFaradayPersistence()
    ) {
        self.sessionStateMachine = sessionStateMachine
        self.enforcement = enforcement
        self.persistence = persistence
        self.lastClassification = persistence.loadStatus()?.lastClassification
        persistStatus()
    }

    @discardableResult
    public func startSession(classification: ProximityClassification, at timestamp: Date = Date()) -> SessionCommand {
        let command = sessionStateMachine.start(classification: classification)
        lastClassification = classification

        if command == .showBeaconMissingAtStart {
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .missingBeacon))
        }
        if command == .none {
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .sessionWaitingForFar))
        }

        persistStatus()
        return command
    }

    @discardableResult
    public func stopSession(at timestamp: Date = Date()) -> SessionCommand {
        let command = sessionStateMachine.stop()
        persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .sessionEnded))
        persistStatus()
        return command
    }

    @discardableResult
    public func handle(classification: ProximityClassification, at timestamp: Date = Date()) -> SessionCommand {
        let command = sessionStateMachine.receive(classification: classification, at: timestamp)
        lastClassification = classification

        if classification == .missing {
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .missingBeacon))
        }

        if command == .beginSession {
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .sessionBegan))
        }

        if command == .requestLock {
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .violation))
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .lockRequested))
            enforcement.requestLock()
        }

        persistStatus()
        return command
    }

    public func saveSettings(_ settings: FaradaySettings) {
        persistence.saveSettings(settings)
    }

    public func loadSettings() -> FaradaySettings? {
        persistence.loadSettings()
    }

    public func saveCalibration(_ calibration: FaradayCalibration) {
        persistence.saveCalibration(calibration)
    }

    public func loadCalibration() -> FaradayCalibration? {
        persistence.loadCalibration()
    }

    public func readStatus() -> FaradayStatus {
        persistence.loadStatus() ?? FaradayStatus(sessionState: sessionStateMachine.state, lastClassification: lastClassification)
    }

    public func readEvents() -> [FaradayEvent] {
        persistence.loadEvents()
    }

    public var state: SessionState {
        sessionStateMachine.state
    }

    private func persistStatus() {
        persistence.saveStatus(FaradayStatus(sessionState: sessionStateMachine.state, lastClassification: lastClassification))
    }
}
