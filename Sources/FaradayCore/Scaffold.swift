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
    case forbidden
    case acceptable
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
    case waitingForAcceptable
    case active
    case unsafe
}

public enum SessionCommand: Equatable {
    case none
    case showBeaconMissingAtStart
    case showBeaconMustBeForbiddenAtStart
    case beginSession
    case endSession
    case requestLock
    case emergencyReasonRequired
    case emergencyPending
    case emergencyActive
    case emergencyExtended
    case emergencyExtensionRefused
    case emergencyExpired
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
        case .forbidden:
            state = .waitingForAcceptable
            return .none
        case .acceptable, .uncertain:
            state = .idle
            return .showBeaconMustBeForbiddenAtStart
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
        case (.waitingForAcceptable, .acceptable):
            state = .active
            activeMissingSince = nil
            lastNonMissingActiveClassification = .acceptable
            return .beginSession
        case (.active, .forbidden):
            state = .unsafe
            activeMissingSince = nil
            lastNonMissingActiveClassification = .forbidden
            return .requestLock
        case (.active, .uncertain):
            activeMissingSince = nil
            lastNonMissingActiveClassification = .uncertain
            return .none
        case (.active, .acceptable):
            activeMissingSince = nil
            lastNonMissingActiveClassification = .acceptable
            return .none
        case (.active, .missing):
            let lastClassification = lastNonMissingActiveClassification
            if lastClassification == .acceptable {
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
        case (.unsafe, .acceptable):
            state = .active
            activeMissingSince = nil
            lastNonMissingActiveClassification = .acceptable
            return .none
        default:
            return .none
        }
    }
}

public struct FaradaySettings: Equatable, Codable {
    public let beacon: BeaconIdentifier?
    public let forbiddenThresholdRSSI: Int
    public let acceptableThresholdRSSI: Int

    public init(beacon: BeaconIdentifier?, forbiddenThresholdRSSI: Int, acceptableThresholdRSSI: Int) {
        self.beacon = beacon
        self.forbiddenThresholdRSSI = forbiddenThresholdRSSI
        self.acceptableThresholdRSSI = acceptableThresholdRSSI
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

public enum CalibrationZone: Equatable, Codable {
    case desk
    case doorwayHall
    case targetRoom
}

public struct GuidedCalibrationOutput: Equatable, Codable {
    public let forbiddenThresholdRSSI: Int
    public let acceptableThresholdRSSI: Int
    public let confidenceNotes: [String]
    public let usedDefaults: Bool

    public init(forbiddenThresholdRSSI: Int, acceptableThresholdRSSI: Int, confidenceNotes: [String], usedDefaults: Bool) {
        self.forbiddenThresholdRSSI = forbiddenThresholdRSSI
        self.acceptableThresholdRSSI = acceptableThresholdRSSI
        self.confidenceNotes = confidenceNotes
        self.usedDefaults = usedDefaults
    }
}

public struct GuidedCalibrationEngine {
    public private(set) var calibration: FaradayCalibration

    public init(calibration: FaradayCalibration = FaradayCalibration()) {
        self.calibration = calibration
    }

    public mutating func record(rssi: Int, at zone: CalibrationZone) {
        switch zone {
        case .desk:
            calibration = FaradayCalibration(
                deskRSSI: calibration.deskRSSI + [rssi],
                doorwayRSSI: calibration.doorwayRSSI,
                targetRoomRSSI: calibration.targetRoomRSSI
            )
        case .doorwayHall:
            calibration = FaradayCalibration(
                deskRSSI: calibration.deskRSSI,
                doorwayRSSI: calibration.doorwayRSSI + [rssi],
                targetRoomRSSI: calibration.targetRoomRSSI
            )
        case .targetRoom:
            calibration = FaradayCalibration(
                deskRSSI: calibration.deskRSSI,
                doorwayRSSI: calibration.doorwayRSSI,
                targetRoomRSSI: calibration.targetRoomRSSI + [rssi]
            )
        }
    }

    public func deriveThresholds(defaultForbiddenThresholdRSSI: Int, defaultAcceptableThresholdRSSI: Int) -> GuidedCalibrationOutput {
        guard
            !calibration.deskRSSI.isEmpty,
            !calibration.doorwayRSSI.isEmpty,
            !calibration.targetRoomRSSI.isEmpty
        else {
            return GuidedCalibrationOutput(
                forbiddenThresholdRSSI: defaultForbiddenThresholdRSSI,
                acceptableThresholdRSSI: defaultAcceptableThresholdRSSI,
                confidenceNotes: ["Calibration incomplete; using default thresholds."],
                usedDefaults: true
            )
        }

        let deskMedian = median(calibration.deskRSSI)
        let doorwayMedian = median(calibration.doorwayRSSI)
        let targetMedian = median(calibration.targetRoomRSSI)

        let forbiddenThreshold = Int((Double(deskMedian + doorwayMedian) / 2.0).rounded())
        let acceptableThreshold = Int((Double(doorwayMedian + targetMedian) / 2.0).rounded())
        let separation = deskMedian - targetMedian

        var notes = ["Calibration complete across desk, doorway/hall, and target room."]
        notes.append(
            separation >= 20
                ? "Strong separation between desk and target room RSSI bands."
                : "Limited separation between desk and target room RSSI bands; expect lower confidence."
        )

        return GuidedCalibrationOutput(
            forbiddenThresholdRSSI: forbiddenThreshold,
            acceptableThresholdRSSI: acceptableThreshold,
            confidenceNotes: notes,
            usedDefaults: false
        )
    }

    private func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count % 2 == 1 {
            return sorted[middle]
        }

        return Int((Double(sorted[middle - 1] + sorted[middle]) / 2.0).rounded())
    }
}

public enum FaradayEventKind: Equatable, Codable {
    case sessionWaitingForAcceptable
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
    private enum EmergencyModeState {
        case idle
        case pending(activateAt: Date, duration: TimeInterval)
        case active(expiresAt: Date, extensionUsed: Bool)
    }

    private var sessionStateMachine: FocusSessionStateMachine
    private let enforcement: EnforcementAdapting
    private let persistence: FaradayPersisting
    private var lastClassification: ProximityClassification?
    private var emergencyModeState: EmergencyModeState = .idle
    private var requiresAcceptableAfterEmergency = false

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
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .sessionWaitingForAcceptable))
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
        processEmergencyTimer(at: timestamp)

        lastClassification = classification

        if classification == .missing {
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .missingBeacon))
        }

        if requiresAcceptableAfterEmergency {
            if classification == .acceptable {
                requiresAcceptableAfterEmergency = false
                if sessionStateMachine.state == .unsafe {
                    _ = sessionStateMachine.receive(classification: .acceptable, at: timestamp)
                }
            }
            persistStatus()
            return .none
        }

        let command = sessionStateMachine.receive(classification: classification, at: timestamp)

        if command == .beginSession {
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .sessionBegan))
        }

        if command == .requestLock {
            let isEmergencySuppressingLock: Bool
            switch emergencyModeState {
            case .pending, .active:
                isEmergencySuppressingLock = true
            case .idle:
                isEmergencySuppressingLock = false
            }

            if !isEmergencySuppressingLock {
                persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .violation))
                persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .lockRequested))
                enforcement.requestLock()
            }
        }

        persistStatus()
        return command == .requestLock ? (isEmergencyActiveOrPending ? .none : .requestLock) : command
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

    @discardableResult
    public func requestEmergencyCowork(
        reason: String,
        at timestamp: Date = Date(),
        activationDelay: TimeInterval = 30,
        duration: TimeInterval = 600
    ) -> SessionCommand {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .emergencyReasonRequired
        }

        let safeDelay = min(max(activationDelay, 30), 60)
        emergencyModeState = .pending(activateAt: timestamp.addingTimeInterval(safeDelay), duration: max(1, duration))
        persistStatus()
        return .emergencyPending
    }

    @discardableResult
    public func extendEmergencyCowork(at timestamp: Date = Date(), duration: TimeInterval = 600) -> SessionCommand {
        processEmergencyTimer(at: timestamp)

        guard case let .active(expiresAt, extensionUsed) = emergencyModeState, !extensionUsed else {
            persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .emergencyRefused))
            persistStatus()
            return .emergencyExtensionRefused
        }

        emergencyModeState = .active(expiresAt: expiresAt.addingTimeInterval(max(1, duration)), extensionUsed: true)
        persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .emergencyExtended))
        persistStatus()
        return .emergencyExtended
    }

    @discardableResult
    public func tick(at timestamp: Date = Date()) -> SessionCommand {
        processEmergencyTimer(at: timestamp)
        persistStatus()

        switch emergencyModeState {
        case .pending:
            return .emergencyPending
        case .active:
            return .emergencyActive
        case .idle:
            return requiresAcceptableAfterEmergency ? .emergencyExpired : .none
        }
    }

    public var state: SessionState {
        sessionStateMachine.state
    }

    private var isEmergencyActiveOrPending: Bool {
        switch emergencyModeState {
        case .pending, .active:
            return true
        case .idle:
            return false
        }
    }

    private func processEmergencyTimer(at timestamp: Date) {
        switch emergencyModeState {
        case let .pending(activateAt, duration):
            if timestamp >= activateAt {
                emergencyModeState = .active(expiresAt: activateAt.addingTimeInterval(duration), extensionUsed: false)
                persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .emergencyStarted))
            }
        case let .active(expiresAt, _):
            if timestamp >= expiresAt {
                emergencyModeState = .idle
                requiresAcceptableAfterEmergency = true
                persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .emergencyExpired))
            }
        case .idle:
            break
        }
    }

    private func persistStatus() {
        persistence.saveStatus(FaradayStatus(sessionState: sessionStateMachine.state, lastClassification: lastClassification))
    }
}
