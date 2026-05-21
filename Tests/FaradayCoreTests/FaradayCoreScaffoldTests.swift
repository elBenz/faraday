import Testing
@testable import FaradayCore

struct FaradayCoreScaffoldTests {
    @Test
    func classificationTracerRecordsOnlyTransitions() {
        let tracer = RSSIClassificationTracer()
        let start = Date(timeIntervalSince1970: 1_000)

        tracer.record(.uncertain, at: start)
        tracer.record(.uncertain, at: start.addingTimeInterval(1))
        tracer.record(.far, at: start.addingTimeInterval(2))

        #expect(tracer.entries.count == 2)
        #expect(tracer.entries.map(\.classification) == [.uncertain, .far])
    }

    @Test
    func classificationTracerRespectsCapacity() {
        let tracer = RSSIClassificationTracer(maxEntries: 2)
        let start = Date(timeIntervalSince1970: 2_000)

        tracer.record(.near, at: start)
        tracer.record(.far, at: start.addingTimeInterval(1))
        tracer.record(.missing, at: start.addingTimeInterval(2))

        #expect(tracer.entries.count == 2)
        #expect(tracer.entries.map(\.classification) == [.far, .missing])
    }

    @Test
    func startRejectsMissingBeacon() {
        var machine = FocusSessionStateMachine()

        let command = machine.start(classification: .missing)

        #expect(command == .showBeaconMissingAtStart)
        #expect(machine.state == .idle)
    }

    @Test
    func startRequiresBeaconToBeNear() {
        var machine = FocusSessionStateMachine()

        let farCommand = machine.start(classification: .far)
        #expect(farCommand == .showBeaconMustBeNearAtStart)
        #expect(machine.state == .idle)

        let uncertainCommand = machine.start(classification: .uncertain)
        #expect(uncertainCommand == .showBeaconMustBeNearAtStart)
        #expect(machine.state == .idle)
    }

    @Test
    func sessionBecomesActiveAfterFarConfirmation() {
        var machine = FocusSessionStateMachine()

        _ = machine.start(classification: .near)
        let command = machine.receive(classification: .far)

        #expect(command == .beginSession)
        #expect(machine.state == .active)
    }

    @Test
    func activeSessionRequestsLockWhenBeaconReturnsNear() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(enforcement: enforcement)

        _ = core.startSession(classification: .near)
        _ = core.handle(classification: .far)
        let command = core.handle(classification: .near)

        #expect(command == .requestLock)
        #expect(enforcement.requestLockCount == 1)
    }

    @Test
    func unsafeProximityLocksOnceUntilFarConfirmedAgain() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(enforcement: enforcement)

        _ = core.startSession(classification: .near)
        _ = core.handle(classification: .far)

        let firstUnsafeCommand = core.handle(classification: .near)
        let repeatedUnsafeCommand = core.handle(classification: .near)
        let clearUnsafeCommand = core.handle(classification: .far)
        let unsafeAgainCommand = core.handle(classification: .near)

        #expect(firstUnsafeCommand == .requestLock)
        #expect(repeatedUnsafeCommand == .none)
        #expect(clearUnsafeCommand == .none)
        #expect(unsafeAgainCommand == .requestLock)
        #expect(core.state == .unsafe)
        #expect(enforcement.requestLockCount == 2)
    }

    @Test
    func missingAfterFarUsesGraceBeforeLocking() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(
            sessionStateMachine: FocusSessionStateMachine(missingBeaconGracePeriod: 5),
            enforcement: enforcement
        )
        let start = Date(timeIntervalSince1970: 9_000)

        _ = core.startSession(classification: .near)
        _ = core.handle(classification: .far, at: start)

        let entersGrace = core.handle(classification: .missing, at: start.addingTimeInterval(1))
        let stillGrace = core.handle(classification: .missing, at: start.addingTimeInterval(5.9))
        let expiresGrace = core.handle(classification: .missing, at: start.addingTimeInterval(6.1))

        #expect(entersGrace == .none)
        #expect(stillGrace == .none)
        #expect(expiresGrace == .requestLock)
        #expect(core.state == .unsafe)
        #expect(enforcement.requestLockCount == 1)
    }

    @Test
    func missingOutsideStrictSessionDoesNotLock() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(enforcement: enforcement)

        let command = core.handle(classification: .missing)

        #expect(command == .none)
        #expect(core.state == .idle)
        #expect(enforcement.requestLockCount == 0)
    }

    @Test
    func missingAfterUncertainLocksImmediately() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(
            sessionStateMachine: FocusSessionStateMachine(missingBeaconGracePeriod: 5),
            enforcement: enforcement
        )
        let start = Date(timeIntervalSince1970: 10_000)

        _ = core.startSession(classification: .near)
        _ = core.handle(classification: .far, at: start)
        _ = core.handle(classification: .uncertain, at: start.addingTimeInterval(1))
        let command = core.handle(classification: .missing, at: start.addingTimeInterval(2))

        #expect(command == .requestLock)
        #expect(core.state == .unsafe)
        #expect(enforcement.requestLockCount == 1)
    }

    @Test
    func allowlistScannerEmitsOnlyMatchingBeaconObservations() {
        let allowlisted = BeaconIdentifier(uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!, major: 100, minor: 7)
        let scanner = BeaconAllowlistScanner(allowlist: [allowlisted])
        let timestamp = Date(timeIntervalSince1970: 5_000)

        scanner.start()
        scanner.ingest(BeaconAdvertisement(identifier: allowlisted, timestamp: timestamp, rssi: -71))
        scanner.ingest(BeaconAdvertisement(identifier: BeaconIdentifier(uuid: allowlisted.uuid, major: 100, minor: 8), timestamp: timestamp.addingTimeInterval(1), rssi: -40))

        #expect(scanner.observations == [BeaconObservation(timestamp: timestamp, rssi: -71)])
    }

    @Test
    func allowlistScannerRequiresStartAndStopsCleanly() {
        let allowlisted = BeaconIdentifier(uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!, major: 100, minor: 7)
        let scanner = BeaconAllowlistScanner(allowlist: [allowlisted])
        let timestamp = Date(timeIntervalSince1970: 6_000)
        let advertisement = BeaconAdvertisement(identifier: allowlisted, timestamp: timestamp, rssi: -68)

        scanner.ingest(advertisement)
        #expect(scanner.observations.isEmpty)

        scanner.start()
        scanner.ingest(advertisement)
        #expect(scanner.observations.count == 1)

        scanner.stop()
        scanner.ingest(advertisement)
        #expect(scanner.observations.count == 1)
    }

    @Test
    func allowlistScannerValidatesFirstMatchingBeacon() {
        let allowlisted = BeaconIdentifier(uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!, major: 100, minor: 7)
        let other = BeaconIdentifier(uuid: allowlisted.uuid, major: 999, minor: 1)
        let scanner = BeaconAllowlistScanner(allowlist: [allowlisted])
        let firstSeenAt = Date(timeIntervalSince1970: 7_000)

        scanner.start()
        scanner.ingest(BeaconAdvertisement(identifier: other, timestamp: firstSeenAt, rssi: -45))
        #expect(scanner.firstValidatedBeacon == nil)

        scanner.ingest(BeaconAdvertisement(identifier: allowlisted, timestamp: firstSeenAt.addingTimeInterval(1), rssi: -70))
        scanner.ingest(BeaconAdvertisement(identifier: allowlisted, timestamp: firstSeenAt.addingTimeInterval(2), rssi: -80))

        #expect(scanner.firstValidatedBeacon?.identifier == allowlisted)
        #expect(scanner.firstValidatedBeacon?.timestamp == firstSeenAt.addingTimeInterval(1))
        #expect(scanner.firstValidatedBeacon?.rssi == -70)
    }

    @Test
    func persistenceCapturesSettingsStatusAndMajorEvents() {
        let persistence = InMemoryFaradayPersistence()
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(
            sessionStateMachine: FocusSessionStateMachine(missingBeaconGracePeriod: 1),
            enforcement: enforcement,
            persistence: persistence
        )
        let beacon = BeaconIdentifier(uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!, major: 10, minor: 11)
        let settings = FaradaySettings(beacon: beacon, nearThresholdRSSI: -70, farThresholdRSSI: -82)
        let t0 = Date(timeIntervalSince1970: 20_000)

        core.saveSettings(settings)
        #expect(core.loadSettings() == settings)

        _ = core.startSession(classification: .near, at: t0)
        _ = core.handle(classification: .far, at: t0.addingTimeInterval(1))
        _ = core.handle(classification: .missing, at: t0.addingTimeInterval(2.1))

        let eventKinds = core.readEvents().map(\.kind)
        #expect(eventKinds == [.sessionWaitingForFar, .sessionBegan, .missingBeacon, .violation, .lockRequested])

        let status = core.readStatus()
        #expect(status.sessionState == .unsafe)
        #expect(status.lastClassification == .missing)
        #expect(enforcement.requestLockCount == 1)
    }

    @Test
    func calibrationDerivesThresholdsAndConfidenceFromGuidedSamples() {
        var engine = GuidedCalibrationEngine()

        [-54, -56, -53, -55].forEach { engine.record(rssi: $0, at: .desk) }
        [-74, -72, -73, -71].forEach { engine.record(rssi: $0, at: .doorwayHall) }
        [-88, -90, -89, -87].forEach { engine.record(rssi: $0, at: .targetRoom) }

        let output = engine.deriveThresholds(defaultNearThresholdRSSI: -65, defaultFarThresholdRSSI: -78)

        #expect(output.nearThresholdRSSI == -64)
        #expect(output.farThresholdRSSI == -81)
        #expect(output.usedDefaults == false)
        #expect(output.confidenceNotes.contains("Calibration complete across desk, doorway/hall, and target room."))
        #expect(output.confidenceNotes.contains("Strong separation between desk and target room RSSI bands."))
    }

    @Test
    func calibrationFallsBackToDefaultsWhenGuidedPathIncomplete() {
        var engine = GuidedCalibrationEngine()
        [-58, -59].forEach { engine.record(rssi: $0, at: .desk) }

        let output = engine.deriveThresholds(defaultNearThresholdRSSI: -65, defaultFarThresholdRSSI: -78)

        #expect(output.nearThresholdRSSI == -65)
        #expect(output.farThresholdRSSI == -78)
        #expect(output.usedDefaults == true)
        #expect(output.confidenceNotes.contains("Calibration incomplete; using default thresholds."))
    }

    @Test
    func jsonPersistenceRoundTripsSettingsAndEvents() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONFaradayPersistence(baseDirectoryURL: tempDirectory)
        let beacon = BeaconIdentifier(uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!, major: 1, minor: 2)
        let settings = FaradaySettings(beacon: beacon, nearThresholdRSSI: -65, farThresholdRSSI: -80)
        let timestamp = Date(timeIntervalSince1970: 30_000)

        store.saveSettings(settings)
        store.appendEvent(FaradayEvent(timestamp: timestamp, kind: .sessionBegan))

        #expect(store.loadSettings() == settings)
        #expect(store.loadEvents() == [FaradayEvent(timestamp: timestamp, kind: .sessionBegan)])
    }
}

final class SpyEnforcementAdapter: EnforcementAdapting {
    private(set) var requestLockCount = 0

    func requestLock() {
        requestLockCount += 1
    }
}
