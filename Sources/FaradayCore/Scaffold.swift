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

public enum IBeaconParser {
    public static func parse(manufacturerData: Data) -> BeaconIdentifier? {
        guard manufacturerData.count >= 25 else { return nil }
        guard manufacturerData[0] == 0x4C, manufacturerData[1] == 0x00 else { return nil }
        guard manufacturerData[2] == 0x02, manufacturerData[3] == 0x15 else { return nil }

        let uuidBytes = manufacturerData[4..<20]
        let major = Int(manufacturerData[20]) << 8 | Int(manufacturerData[21])
        let minor = Int(manufacturerData[22]) << 8 | Int(manufacturerData[23])

        let hex = uuidBytes.map { String(format: "%02x", $0) }.joined()
        let formatted = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"

        guard let uuid = UUID(uuidString: String(formatted)) else { return nil }
        return BeaconIdentifier(uuid: uuid, major: major, minor: minor)
    }
}

public struct BeaconScanCandidate: Equatable {
    public let identifier: BeaconIdentifier
    public let lastSeen: Date
    public let lastRSSI: Int
    public let seenCount: Int

    public init(identifier: BeaconIdentifier, lastSeen: Date, lastRSSI: Int, seenCount: Int) {
        self.identifier = identifier
        self.lastSeen = lastSeen
        self.lastRSSI = lastRSSI
        self.seenCount = seenCount
    }
}

public final class IBeaconCandidateTracker {
    private var candidates: [BeaconIdentifier: BeaconScanCandidate] = [:]

    public init() {}

    public func ingest(_ advertisement: BeaconAdvertisement) {
        if let existing = candidates[advertisement.identifier] {
            candidates[advertisement.identifier] = BeaconScanCandidate(
                identifier: advertisement.identifier,
                lastSeen: advertisement.timestamp,
                lastRSSI: advertisement.rssi,
                seenCount: existing.seenCount + 1
            )
        } else {
            candidates[advertisement.identifier] = BeaconScanCandidate(
                identifier: advertisement.identifier,
                lastSeen: advertisement.timestamp,
                lastRSSI: advertisement.rssi,
                seenCount: 1
            )
        }
    }

    public func list() -> [BeaconScanCandidate] {
        candidates.values.sorted { lhs, rhs in
            if lhs.lastSeen == rhs.lastSeen {
                return lhs.identifier.uuid.uuidString < rhs.identifier.uuid.uuidString
            }
            return lhs.lastSeen > rhs.lastSeen
        }
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

public enum CalibrationConfidence: Equatable, Codable {
    case good
    case weak
    case unusable
}

public final class CalibratedProximityClassifier {
    private let forbiddenThresholdRSSI: Int
    private let acceptableThresholdRSSI: Int
    private let forbiddenSustain: TimeInterval
    private let acceptableSustain: TimeInterval
    private let missingTimeout: TimeInterval

    private var lastObservationAt: Date?
    private var currentStableClassification: ProximityClassification = .uncertain
    private var candidateClassification: ProximityClassification?
    private var candidateSince: Date?

    public init(
        forbiddenThresholdRSSI: Int,
        acceptableThresholdRSSI: Int,
        forbiddenSustain: TimeInterval = 5,
        acceptableSustain: TimeInterval = 15,
        missingTimeout: TimeInterval = 10
    ) {
        self.forbiddenThresholdRSSI = forbiddenThresholdRSSI
        self.acceptableThresholdRSSI = acceptableThresholdRSSI
        self.forbiddenSustain = max(0, forbiddenSustain)
        self.acceptableSustain = max(0, acceptableSustain)
        self.missingTimeout = max(0, missingTimeout)
    }

    public func classify(rssi: Int, at timestamp: Date = Date()) -> ProximityClassification {
        lastObservationAt = timestamp

        let raw: ProximityClassification
        if rssi >= forbiddenThresholdRSSI {
            raw = .forbidden
        } else if rssi <= acceptableThresholdRSSI {
            raw = .acceptable
        } else {
            raw = .uncertain
        }

        switch raw {
        case .forbidden:
            return sustain(raw: .forbidden, at: timestamp, required: forbiddenSustain)
        case .acceptable:
            return sustain(raw: .acceptable, at: timestamp, required: acceptableSustain)
        case .uncertain, .missing:
            candidateClassification = nil
            candidateSince = nil
            currentStableClassification = .uncertain
            return .uncertain
        }
    }

    public func classify(at timestamp: Date = Date()) -> ProximityClassification {
        guard let lastObservationAt else {
            return .missing
        }

        if timestamp.timeIntervalSince(lastObservationAt) >= missingTimeout {
            currentStableClassification = .missing
            candidateClassification = nil
            candidateSince = nil
            return .missing
        }

        return currentStableClassification
    }

    public static func evaluateConfidence(forbiddenRSSISamples: [Int], acceptableRSSISamples: [Int]) -> CalibrationConfidence {
        guard !forbiddenRSSISamples.isEmpty, !acceptableRSSISamples.isEmpty else {
            return .unusable
        }

        let forbiddenMedian = median(forbiddenRSSISamples)
        let acceptableMedian = median(acceptableRSSISamples)
        let separation = forbiddenMedian - acceptableMedian

        let forbiddenMin = forbiddenRSSISamples.min() ?? forbiddenMedian
        let acceptableMax = acceptableRSSISamples.max() ?? acceptableMedian
        let overlap = acceptableMax >= forbiddenMin

        if !overlap, separation >= 15 {
            return .good
        }

        if separation >= 8 {
            return .weak
        }

        return .unusable
    }

    public static func isArmedEnforcementEligible(confidence: CalibrationConfidence) -> Bool {
        confidence == .good
    }

    private func sustain(raw: ProximityClassification, at timestamp: Date, required: TimeInterval) -> ProximityClassification {
        if candidateClassification != raw {
            candidateClassification = raw
            candidateSince = timestamp
            currentStableClassification = .uncertain
            return .uncertain
        }

        guard let candidateSince else {
            candidateSince = timestamp
            currentStableClassification = .uncertain
            return .uncertain
        }

        if timestamp.timeIntervalSince(candidateSince) >= required {
            currentStableClassification = raw
            return raw
        }

        currentStableClassification = .uncertain
        return .uncertain
    }

    private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[middle]
        }

        return Int((Double(sorted[middle - 1] + sorted[middle]) / 2.0).rounded())
    }
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
    case dryRunLockSkipped
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

public enum EnforcementMode: Equatable, Codable {
    case dryRun
    case armed
}

public enum ObservationSource: Equatable, Codable {
    case live
    case simulation
}

public enum OverlayState: Equatable, Codable {
    case hidden
    case showingViolation
}

public protocol OverlayAdapting {
    func showViolation()
    func hide()
}

public final class NoopOverlayAdapter: OverlayAdapting {
    public init() {}
    public func showViolation() {}
    public func hide() {}
}

public struct FaradayStatus: Equatable, Codable {
    public let sessionState: SessionState
    public let lastClassification: ProximityClassification?
    public let enforcementMode: EnforcementMode
    public let observationSource: ObservationSource
    public let overlayState: OverlayState

    public init(
        sessionState: SessionState,
        lastClassification: ProximityClassification?,
        enforcementMode: EnforcementMode = .dryRun,
        observationSource: ObservationSource = .live,
        overlayState: OverlayState = .hidden
    ) {
        self.sessionState = sessionState
        self.lastClassification = lastClassification
        self.enforcementMode = enforcementMode
        self.observationSource = observationSource
        self.overlayState = overlayState
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
        eventsURL = baseDirectoryURL.appendingPathComponent("events.jsonl")
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
        guard let data = try? encoder.encode(event),
              let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8)
        else { return }

        if let handle = try? FileHandle(forWritingTo: eventsURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            return
        }

        try? line.write(to: eventsURL, options: .atomic)
    }

    public func loadEvents() -> [FaradayEvent] {
        guard let raw = try? String(contentsOf: eventsURL, encoding: .utf8) else {
            return []
        }

        return raw
            .split(whereSeparator: \Character.isNewline)
            .compactMap { line in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(FaradayEvent.self, from: data)
            }
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

public enum SimulationScenario: Equatable {
    case startActivationViolationDryRun
    case missingDegraded
}

public struct SimulationReplayResult: Equatable {
    public let commands: [SessionCommand]

    public init(commands: [SessionCommand]) {
        self.commands = commands
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
    private let overlay: OverlayAdapting
    private var lastClassification: ProximityClassification?
    private var emergencyModeState: EmergencyModeState = .idle
    private var requiresAcceptableAfterEmergency = false
    private var enforcementMode: EnforcementMode
    private let candidateTracker = IBeaconCandidateTracker()
    private var selectedBeaconScanner: BeaconAllowlistScanner?
    private var observationSource: ObservationSource
    private var overlayState: OverlayState

    public init(
        sessionStateMachine: FocusSessionStateMachine = FocusSessionStateMachine(),
        enforcement: EnforcementAdapting = NoopEnforcementAdapter(),
        overlay: OverlayAdapting = NoopOverlayAdapter(),
        persistence: FaradayPersisting = InMemoryFaradayPersistence()
    ) {
        self.sessionStateMachine = sessionStateMachine
        self.enforcement = enforcement
        self.persistence = persistence
        self.overlay = overlay
        let persistedStatus = persistence.loadStatus()
        self.lastClassification = persistedStatus?.lastClassification
        self.enforcementMode = persistedStatus?.enforcementMode ?? .dryRun
        self.observationSource = persistedStatus?.observationSource ?? .live
        self.overlayState = persistedStatus?.overlayState ?? .hidden

        if let beacon = persistence.loadSettings()?.beacon {
            let scanner = BeaconAllowlistScanner(allowlist: [beacon])
            scanner.start()
            self.selectedBeaconScanner = scanner
        }

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
        if overlayState != .hidden {
            overlay.hide()
            overlayState = .hidden
        }
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
                if overlayState != .showingViolation {
                    overlay.showViolation()
                    overlayState = .showingViolation
                }
                if enforcementMode == .armed {
                    enforcement.requestLock()
                } else {
                    persistence.appendEvent(FaradayEvent(timestamp: timestamp, kind: .dryRunLockSkipped))
                }
            }
        }

        if sessionStateMachine.state == .active && overlayState != .hidden {
            overlay.hide()
            overlayState = .hidden
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
        persistence.loadStatus() ?? FaradayStatus(
            sessionState: sessionStateMachine.state,
            lastClassification: lastClassification,
            enforcementMode: enforcementMode,
            observationSource: observationSource,
            overlayState: overlayState
        )
    }

    public func setEnforcementMode(_ mode: EnforcementMode) {
        enforcementMode = mode
        persistStatus()
    }

    @discardableResult
    public func simulateInjection(_ classification: ProximityClassification, at timestamp: Date = Date()) -> SessionCommand {
        observationSource = .simulation

        if state == .idle {
            return startSession(classification: classification, at: timestamp)
        }

        return handle(classification: classification, at: timestamp)
    }

    @discardableResult
    public func replaySimulationScenario(_ scenario: SimulationScenario, at timestamp: Date = Date()) -> SimulationReplayResult {
        setEnforcementMode(.dryRun)

        switch scenario {
        case .startActivationViolationDryRun:
            _ = stopSession(at: timestamp)
            let commands: [SessionCommand] = [
                simulateInjection(.forbidden, at: timestamp),
                simulateInjection(.acceptable, at: timestamp.addingTimeInterval(1)),
                simulateInjection(.forbidden, at: timestamp.addingTimeInterval(2))
            ]
            return SimulationReplayResult(commands: commands)

        case .missingDegraded:
            _ = stopSession(at: timestamp)
            let commands: [SessionCommand] = [
                simulateInjection(.forbidden, at: timestamp),
                simulateInjection(.acceptable, at: timestamp.addingTimeInterval(1)),
                simulateInjection(.missing, at: timestamp.addingTimeInterval(2)),
                simulateInjection(.missing, at: timestamp.addingTimeInterval(13))
            ]
            return SimulationReplayResult(commands: commands)
        }
    }

    public func readEvents() -> [FaradayEvent] {
        persistence.loadEvents()
    }

    @discardableResult
    public func ingestIBeaconScan(manufacturerData: Data, rssi: Int, at timestamp: Date = Date()) -> Bool {
        guard let identifier = IBeaconParser.parse(manufacturerData: manufacturerData) else {
            return false
        }

        let advertisement = BeaconAdvertisement(identifier: identifier, timestamp: timestamp, rssi: rssi)
        candidateTracker.ingest(advertisement)
        selectedBeaconScanner?.ingest(advertisement)
        return true
    }

    public func listBeaconCandidates() -> [BeaconScanCandidate] {
        candidateTracker.list()
    }

    public func selectBeaconIdentity(_ identifier: BeaconIdentifier) {
        let current = persistence.loadSettings()
        persistence.saveSettings(
            FaradaySettings(
                beacon: identifier,
                forbiddenThresholdRSSI: current?.forbiddenThresholdRSSI ?? -65,
                acceptableThresholdRSSI: current?.acceptableThresholdRSSI ?? -80
            )
        )

        let scanner = BeaconAllowlistScanner(allowlist: [identifier])
        scanner.start()
        selectedBeaconScanner = scanner
    }

    public func selectedBeaconLiveObservations(limit: Int = 20) -> [BeaconObservation] {
        guard let scanner = selectedBeaconScanner else { return [] }
        let safeLimit = max(1, limit)
        if scanner.observations.count <= safeLimit {
            return scanner.observations
        }
        return Array(scanner.observations.suffix(safeLimit))
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
        persistence.saveStatus(
            FaradayStatus(
                sessionState: sessionStateMachine.state,
                lastClassification: lastClassification,
                enforcementMode: enforcementMode,
                observationSource: observationSource,
                overlayState: overlayState
            )
        )
    }
}

public final class FaradayRPCService {
    private let core: FaradayCore
    private let encoder = JSONEncoder()
    private let iso8601 = ISO8601DateFormatter()

    public init(core: FaradayCore) {
        self.core = core
    }

    public func handle(requestData: Data) -> Data? {
        guard
            let object = try? JSONSerialization.jsonObject(with: requestData),
            let request = object as? [String: Any],
            request["jsonrpc"] as? String == "2.0",
            let method = request["method"] as? String
        else {
            return response(id: nil, error: ["code": -32600, "message": "Invalid Request"])
        }

        let id = request["id"]
        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "faraday.status":
            let status = core.readStatus()
            return response(id: id, result: [
                "sessionState": status.sessionState.rpcName,
                "lastClassification": status.lastClassification?.rpcName as Any,
                "enforcementMode": status.enforcementMode.rpcName,
                "observationSource": status.observationSource.rpcName,
                "calibrationConfidence": NSNull(),
                "overlayState": status.overlayState.rpcName,
                "countdownSeconds": NSNull()
            ])

        case "session.start":
            guard let rawClassification = params["classification"] as? String,
                  let classification = ProximityClassification(rpcName: rawClassification) else {
                return response(id: id, error: ["code": -32602, "message": "Invalid params: classification is required"])
            }
            let command = core.startSession(classification: classification)
            return response(id: id, result: ["command": command.rpcName])

        case "session.stop":
            let command = core.stopSession()
            return response(id: id, result: ["command": command.rpcName])

        case "enforcement.setMode":
            guard let rawMode = params["mode"] as? String,
                  let mode = EnforcementMode(rpcName: rawMode) else {
                return response(id: id, error: ["code": -32602, "message": "Invalid params: mode must be dryRun or armed"])
            }
            core.setEnforcementMode(mode)
            return response(id: id, result: ["enforcementMode": mode.rpcName])

        case "simulation.inject":
            guard let rawClassification = params["classification"] as? String,
                  let classification = ProximityClassification(rpcName: rawClassification) else {
                return response(id: id, error: ["code": -32602, "message": "Invalid params: classification is required"])
            }
            let command = core.simulateInjection(classification)
            return response(id: id, result: ["command": command.rpcName])

        case "simulation.replay":
            guard let rawScenario = params["scenario"] as? String,
                  let scenario = SimulationScenario(rpcName: rawScenario) else {
                return response(id: id, error: ["code": -32602, "message": "Invalid params: scenario is required"])
            }
            let replay = core.replaySimulationScenario(scenario)
            return response(id: id, result: ["commands": replay.commands.map(\.rpcName)])

        case "events.tail":
            let afterIndex = params["afterIndex"] as? Int ?? -1
            let events = core.readEvents()
            let startIndex = min(max(afterIndex + 1, 0), events.count)
            let tail = events[startIndex...].enumerated().map { offset, event in
                [
                    "index": startIndex + offset,
                    "timestamp": iso8601.string(from: event.timestamp),
                    "kind": event.kind.rpcName
                ]
            }
            return response(id: id, result: ["events": tail, "nextIndex": events.count - 1])

        case "beacon.scanIngest":
            guard let hex = params["manufacturerDataHex"] as? String,
                  let data = Data(hexString: hex),
                  let rssi = params["rssi"] as? Int else {
                return response(id: id, error: ["code": -32602, "message": "Invalid params: manufacturerDataHex and rssi are required"])
            }
            let accepted = core.ingestIBeaconScan(manufacturerData: data, rssi: rssi)
            return response(id: id, result: ["accepted": accepted])

        case "beacon.scanCandidates":
            let candidates = core.listBeaconCandidates().map { candidate in
                [
                    "uuid": candidate.identifier.uuid.uuidString.lowercased(),
                    "major": candidate.identifier.major,
                    "minor": candidate.identifier.minor,
                    "lastSeen": iso8601.string(from: candidate.lastSeen),
                    "lastRSSI": candidate.lastRSSI,
                    "seenCount": candidate.seenCount
                ]
            }
            return response(id: id, result: ["candidates": candidates])

        case "beacon.select":
            guard
                let uuidRaw = params["uuid"] as? String,
                let uuid = UUID(uuidString: uuidRaw),
                let major = params["major"] as? Int,
                let minor = params["minor"] as? Int
            else {
                return response(id: id, error: ["code": -32602, "message": "Invalid params: uuid, major, and minor are required"])
            }
            core.selectBeaconIdentity(BeaconIdentifier(uuid: uuid, major: major, minor: minor))
            return response(id: id, result: ["saved": true])

        case "beacon.liveRSSI":
            let samples = core.selectedBeaconLiveObservations().map { sample in
                [
                    "timestamp": iso8601.string(from: sample.timestamp),
                    "rssi": sample.rssi
                ]
            }
            return response(id: id, result: ["selected": core.loadSettings()?.beacon != nil, "samples": samples])

        case "calibration.evaluate":
            guard
                let forbidden = params["forbiddenRSSISamples"] as? [Int],
                let acceptable = params["acceptableRSSISamples"] as? [Int],
                !forbidden.isEmpty,
                !acceptable.isEmpty
            else {
                return response(id: id, error: ["code": -32602, "message": "Invalid params: forbiddenRSSISamples and acceptableRSSISamples are required"])
            }

            let confidence = CalibratedProximityClassifier.evaluateConfidence(
                forbiddenRSSISamples: forbidden,
                acceptableRSSISamples: acceptable
            )
            let forbiddenMedian = Self.median(forbidden)
            let acceptableMedian = Self.median(acceptable)
            return response(id: id, result: [
                "confidence": confidence.rpcName,
                "armedEligible": CalibratedProximityClassifier.isArmedEnforcementEligible(confidence: confidence),
                "forbiddenMedian": forbiddenMedian,
                "acceptableMedian": acceptableMedian,
                "separation": forbiddenMedian - acceptableMedian
            ])

        default:
            return response(id: id, error: ["code": -32601, "message": "Method not found"])
        }
    }

    private static func median(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[middle]
        }
        return Int((Double(sorted[middle - 1] + sorted[middle]) / 2.0).rounded())
    }

    private func response(id: Any?, result: [String: Any]? = nil, error: [String: Any]? = nil) -> Data? {
        var payload: [String: Any] = ["jsonrpc": "2.0", "id": id as Any]
        if let result {
            payload["result"] = result
        }
        if let error {
            payload["error"] = error
        }

        return try? JSONSerialization.data(withJSONObject: payload)
    }
}

private extension ProximityClassification {
    init?(rpcName: String) {
        switch rpcName {
        case "forbidden": self = .forbidden
        case "acceptable": self = .acceptable
        case "uncertain": self = .uncertain
        case "missing": self = .missing
        default: return nil
        }
    }

    var rpcName: String {
        switch self {
        case .forbidden: return "forbidden"
        case .acceptable: return "acceptable"
        case .uncertain: return "uncertain"
        case .missing: return "missing"
        }
    }
}

private extension SessionState {
    var rpcName: String {
        switch self {
        case .idle: return "idle"
        case .waitingForAcceptable: return "waitingForAcceptable"
        case .active: return "active"
        case .unsafe: return "unsafe"
        }
    }
}

private extension SessionCommand {
    var rpcName: String {
        switch self {
        case .none: return "none"
        case .showBeaconMissingAtStart: return "showBeaconMissingAtStart"
        case .showBeaconMustBeForbiddenAtStart: return "showBeaconMustBeForbiddenAtStart"
        case .beginSession: return "beginSession"
        case .endSession: return "endSession"
        case .requestLock: return "requestLock"
        case .emergencyReasonRequired: return "emergencyReasonRequired"
        case .emergencyPending: return "emergencyPending"
        case .emergencyActive: return "emergencyActive"
        case .emergencyExtended: return "emergencyExtended"
        case .emergencyExtensionRefused: return "emergencyExtensionRefused"
        case .emergencyExpired: return "emergencyExpired"
        }
    }
}

private extension FaradayEventKind {
    var rpcName: String {
        switch self {
        case .sessionWaitingForAcceptable: return "sessionWaitingForAcceptable"
        case .sessionBegan: return "sessionBegan"
        case .sessionEnded: return "sessionEnded"
        case .missingBeacon: return "missingBeacon"
        case .violation: return "violation"
        case .lockRequested: return "lockRequested"
        case .dryRunLockSkipped: return "dryRunLockSkipped"
        case .emergencyStarted: return "emergencyStarted"
        case .emergencyExtended: return "emergencyExtended"
        case .emergencyRefused: return "emergencyRefused"
        case .emergencyExpired: return "emergencyExpired"
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else { return nil }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            let byteString = cleaned[index..<next]
            guard let byte = UInt8(byteString, radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}

private extension SimulationScenario {
    init?(rpcName: String) {
        switch rpcName {
        case "startActivationViolationDryRun": self = .startActivationViolationDryRun
        case "missingDegraded": self = .missingDegraded
        default: return nil
        }
    }
}

private extension ObservationSource {
    var rpcName: String {
        switch self {
        case .live: return "live"
        case .simulation: return "simulation"
        }
    }
}

private extension EnforcementMode {
    init?(rpcName: String) {
        switch rpcName {
        case "dryRun": self = .dryRun
        case "armed": self = .armed
        default: return nil
        }
    }

    var rpcName: String {
        switch self {
        case .dryRun: return "dryRun"
        case .armed: return "armed"
        }
    }
}

private extension OverlayState {
    var rpcName: String {
        switch self {
        case .hidden: return "hidden"
        case .showingViolation: return "showingViolation"
        }
    }
}

private extension CalibrationConfidence {
    var rpcName: String {
        switch self {
        case .good: return "good"
        case .weak: return "weak"
        case .unusable: return "unusable"
        }
    }
}
