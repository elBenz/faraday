import Testing
@testable import FaradayCore

struct FaradayCoreScaffoldTests {
    @Test
    func classificationTracerRecordsOnlyTransitions() {
        let tracer = RSSIClassificationTracer()
        let start = Date(timeIntervalSince1970: 1_000)

        tracer.record(.uncertain, at: start)
        tracer.record(.uncertain, at: start.addingTimeInterval(1))
        tracer.record(.acceptable, at: start.addingTimeInterval(2))

        #expect(tracer.entries.count == 2)
        #expect(tracer.entries.map(\.classification) == [.uncertain, .acceptable])
    }

    @Test
    func classificationTracerRespectsCapacity() {
        let tracer = RSSIClassificationTracer(maxEntries: 2)
        let start = Date(timeIntervalSince1970: 2_000)

        tracer.record(.forbidden, at: start)
        tracer.record(.acceptable, at: start.addingTimeInterval(1))
        tracer.record(.missing, at: start.addingTimeInterval(2))

        #expect(tracer.entries.count == 2)
        #expect(tracer.entries.map(\.classification) == [.acceptable, .missing])
    }

    @Test
    func startRejectsMissingBeacon() {
        var machine = FocusSessionStateMachine()

        let command = machine.start(classification: .missing)

        #expect(command == .showBeaconMissingAtStart)
        #expect(machine.state == .idle)
    }

    @Test
    func startRequiresBeaconToBeForbidden() {
        var machine = FocusSessionStateMachine()

        let farCommand = machine.start(classification: .acceptable)
        #expect(farCommand == .showBeaconMustBeForbiddenAtStart)
        #expect(machine.state == .idle)

        let uncertainCommand = machine.start(classification: .uncertain)
        #expect(uncertainCommand == .showBeaconMustBeForbiddenAtStart)
        #expect(machine.state == .idle)
    }

    @Test
    func sessionBecomesActiveAfterAcceptableConfirmation() {
        var machine = FocusSessionStateMachine()

        _ = machine.start(classification: .forbidden)
        let command = machine.receive(classification: .acceptable)

        #expect(command == .beginSession)
        #expect(machine.state == .active)
    }

    @Test
    func activeSessionRequestsLockWhenBeaconReturnsForbidden() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(enforcement: enforcement)
        armForTests(core)

        _ = core.startSession(classification: .forbidden)
        _ = core.handle(classification: .acceptable)
        let command = core.handle(classification: .forbidden)

        #expect(command == .requestLock)
        #expect(enforcement.requestLockCount == 1)
    }

    @Test
    func overlayOrchestrationShowsOnViolationAndHidesOnRecoveryOrStop() {
        let overlay = SpyOverlayAdapter()
        let core = FaradayCore(overlay: overlay)

        _ = core.startSession(classification: .forbidden)
        _ = core.handle(classification: .acceptable)
        _ = core.handle(classification: .forbidden)

        #expect(overlay.events == [.showViolation])
        #expect(core.readStatus().overlayState == .showingViolation)

        _ = core.handle(classification: .acceptable)
        #expect(overlay.events == [.showViolation, .hide])
        #expect(core.readStatus().overlayState == .hidden)

        _ = core.stopSession()
        #expect(overlay.events == [.showViolation, .hide])
    }

    @Test
    func unsafeProximityLocksOnceUntilAcceptableConfirmedAgain() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(enforcement: enforcement)
        armForTests(core)

        _ = core.startSession(classification: .forbidden)
        _ = core.handle(classification: .acceptable)

        let firstUnsafeCommand = core.handle(classification: .forbidden)
        let repeatedUnsafeCommand = core.handle(classification: .forbidden)
        let clearUnsafeCommand = core.handle(classification: .acceptable)
        let unsafeAgainCommand = core.handle(classification: .forbidden)

        #expect(firstUnsafeCommand == .requestLock)
        #expect(repeatedUnsafeCommand == .none)
        #expect(clearUnsafeCommand == .none)
        #expect(unsafeAgainCommand == .requestLock)
        #expect(core.state == .unsafe)
        #expect(enforcement.requestLockCount == 2)
    }

    @Test
    func unlockRecheckEvaluatesClassificationFromUnsafeState() {
        let enforcement = SpyEnforcementAdapter()
        let overlay = SpyOverlayAdapter()
        let core = FaradayCore(
            sessionStateMachine: FocusSessionStateMachine(missingBeaconGracePeriod: 1),
            enforcement: enforcement,
            overlay: overlay
        )
        armForTests(core)
        let t0 = Date(timeIntervalSince1970: 11_000)

        _ = core.startSession(classification: .forbidden, at: t0)
        _ = core.handle(classification: .acceptable, at: t0.addingTimeInterval(1))
        _ = core.handle(classification: .forbidden, at: t0.addingTimeInterval(2))

        let forbiddenRecheck = core.handleUnlockRecheck(classification: .forbidden, at: t0.addingTimeInterval(3))
        #expect(forbiddenRecheck == .requestLock)
        #expect(enforcement.requestLockCount == 2)

        let acceptableRecheck = core.handleUnlockRecheck(classification: .acceptable, at: t0.addingTimeInterval(4))
        #expect(acceptableRecheck == .none)
        #expect(core.state == .active)
        #expect(core.readStatus().overlayState == .hidden)

        _ = core.handle(classification: .forbidden, at: t0.addingTimeInterval(5))
        let missingRecheck = core.handleUnlockRecheck(classification: .missing, at: t0.addingTimeInterval(6))
        #expect(missingRecheck == .none)
        #expect(core.state == .degradedBeaconTrust)
        #expect(overlay.events.contains(.showDegradedBeaconTrust))
    }

    @Test
    func missingAfterAcceptableDegradesWithoutLockingAndRequiresForbiddenThenAcceptableRecovery() {
        let enforcement = SpyEnforcementAdapter()
        let overlay = SpyOverlayAdapter()
        let core = FaradayCore(
            sessionStateMachine: FocusSessionStateMachine(missingBeaconGracePeriod: 5),
            enforcement: enforcement,
            overlay: overlay
        )
        armForTests(core)
        let start = Date(timeIntervalSince1970: 9_000)

        _ = core.startSession(classification: .forbidden)
        _ = core.handle(classification: .acceptable, at: start)

        let entersGrace = core.handle(classification: .missing, at: start.addingTimeInterval(1))
        let degrades = core.handle(classification: .missing, at: start.addingTimeInterval(6.1))
        let acceptableTooSoon = core.handle(classification: .acceptable, at: start.addingTimeInterval(7))
        let revalidateForbidden = core.handle(classification: .forbidden, at: start.addingTimeInterval(8))
        let recoverAcceptable = core.handle(classification: .acceptable, at: start.addingTimeInterval(9))

        #expect(entersGrace == .none)
        #expect(degrades == .none)
        #expect(acceptableTooSoon == .none)
        #expect(revalidateForbidden == .none)
        #expect(recoverAcceptable == .none)
        #expect(core.state == .active)
        #expect(enforcement.requestLockCount == 0)
        #expect(overlay.events.contains(.showDegradedBeaconTrust))
        #expect(overlay.events.last == .hide)
        #expect(core.readEvents().map(\.kind).contains(.beaconTrustDegraded))
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
    func missingAfterUncertainDoesNotLock() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(
            sessionStateMachine: FocusSessionStateMachine(missingBeaconGracePeriod: 1),
            enforcement: enforcement
        )
        armForTests(core)
        let start = Date(timeIntervalSince1970: 10_000)

        _ = core.startSession(classification: .forbidden)
        _ = core.handle(classification: .acceptable, at: start)
        _ = core.handle(classification: .uncertain, at: start.addingTimeInterval(1))
        _ = core.handle(classification: .missing, at: start.addingTimeInterval(2))
        let command = core.handle(classification: .missing, at: start.addingTimeInterval(3.2))

        #expect(command == .none)
        #expect(core.state == .degradedBeaconTrust)
        #expect(enforcement.requestLockCount == 0)
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
    func armedModeRequiresBeaconAndGoodCalibration() {
        let persistence = InMemoryFaradayPersistence()
        let core = FaradayCore(persistence: persistence)

        #expect(core.readStatus().enforcementMode == .dryRun)

        core.setEnforcementMode(.armed)
        #expect(core.readStatus().enforcementMode == .dryRun)

        core.saveSettings(FaradaySettings(
            beacon: BeaconIdentifier(uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!, major: 1, minor: 2),
            forbiddenThresholdRSSI: -65,
            acceptableThresholdRSSI: -80
        ))
        core.saveCalibration(FaradayCalibration(
            deskRSSI: [-66, -67, -65, -68],
            doorwayRSSI: [-72, -73, -71, -74],
            targetRoomRSSI: []
        ))
        core.setEnforcementMode(.armed)
        #expect(core.readStatus().enforcementMode == .dryRun)

        core.saveCalibration(FaradayCalibration(
            deskRSSI: [-56, -57, -55, -58],
            doorwayRSSI: [-84, -85, -83, -86],
            targetRoomRSSI: []
        ))
        core.setEnforcementMode(.armed)
        #expect(core.readStatus().enforcementMode == .armed)
        #expect(persistence.loadStatus()?.enforcementMode == .armed)
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
        armForTests(core)
        let beacon = BeaconIdentifier(uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!, major: 10, minor: 11)
        let settings = FaradaySettings(beacon: beacon, forbiddenThresholdRSSI: -70, acceptableThresholdRSSI: -82)
        let t0 = Date(timeIntervalSince1970: 20_000)

        core.saveSettings(settings)
        #expect(core.loadSettings() == settings)

        _ = core.startSession(classification: .forbidden, at: t0)
        _ = core.handle(classification: .acceptable, at: t0.addingTimeInterval(1))
        _ = core.handle(classification: .missing, at: t0.addingTimeInterval(2.1))
        _ = core.handle(classification: .missing, at: t0.addingTimeInterval(3.2))

        let eventKinds = core.readEvents().map(\.kind)
        #expect(eventKinds == [.sessionWaitingForAcceptable, .sessionBegan, .missingBeacon, .missingBeacon, .beaconTrustDegraded])

        let status = core.readStatus()
        #expect(status.sessionState == .degradedBeaconTrust)
        #expect(status.lastClassification == .missing)
        #expect(enforcement.requestLockCount == 0)
    }

    @Test
    func calibrationDerivesThresholdsAndConfidenceFromGuidedSamples() {
        var engine = GuidedCalibrationEngine()

        [-54, -56, -53, -55].forEach { engine.record(rssi: $0, at: .desk) }
        [-74, -72, -73, -71].forEach { engine.record(rssi: $0, at: .doorwayHall) }
        [-88, -90, -89, -87].forEach { engine.record(rssi: $0, at: .targetRoom) }

        let output = engine.deriveThresholds(defaultForbiddenThresholdRSSI: -65, defaultAcceptableThresholdRSSI: -78)

        #expect(output.forbiddenThresholdRSSI == -64)
        #expect(output.acceptableThresholdRSSI == -81)
        #expect(output.usedDefaults == false)
        #expect(output.confidenceNotes.contains("Calibration complete across desk, doorway/hall, and target room."))
        #expect(output.confidenceNotes.contains("Strong separation between desk and target room RSSI bands."))
    }

    @Test
    func calibrationFallsBackToDefaultsWhenGuidedPathIncomplete() {
        var engine = GuidedCalibrationEngine()
        [-58, -59].forEach { engine.record(rssi: $0, at: .desk) }

        let output = engine.deriveThresholds(defaultForbiddenThresholdRSSI: -65, defaultAcceptableThresholdRSSI: -78)

        #expect(output.forbiddenThresholdRSSI == -65)
        #expect(output.acceptableThresholdRSSI == -78)
        #expect(output.usedDefaults == true)
        #expect(output.confidenceNotes.contains("Calibration incomplete; using default thresholds."))
    }

    @Test
    func emergencyCoworkModeDelayExtensionAndRecovery() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(enforcement: enforcement)
        armForTests(core)
        let start = Date(timeIntervalSince1970: 40_000)

        _ = core.startSession(classification: .forbidden, at: start)
        _ = core.handle(classification: .acceptable, at: start.addingTimeInterval(1))

        let missingReason = core.requestEmergencyCowork(reason: "", at: start.addingTimeInterval(2))
        #expect(missingReason == .emergencyReasonRequired)

        let pending = core.requestEmergencyCowork(
            reason: "Need MFA approval",
            at: start.addingTimeInterval(2),
            activationDelay: 30,
            duration: 600
        )
        #expect(pending == .emergencyPending)

        let lockSuppressed = core.handle(classification: .forbidden, at: start.addingTimeInterval(3))
        #expect(lockSuppressed == .none)
        #expect(enforcement.requestLockCount == 0)

        let active = core.tick(at: start.addingTimeInterval(32))
        #expect(active == .emergencyActive)

        let extension = core.extendEmergencyCowork(at: start.addingTimeInterval(100), duration: 600)
        let extensionRefused = core.extendEmergencyCowork(at: start.addingTimeInterval(101), duration: 600)
        #expect(extension == .emergencyExtended)
        #expect(extensionRefused == .emergencyExtensionRefused)

        let expired = core.tick(at: start.addingTimeInterval(1_301))
        #expect(expired == .emergencyExpired)

        let forbiddenAfterExpiry = core.handle(classification: .forbidden, at: start.addingTimeInterval(1_302))
        let acceptableRecovery = core.handle(classification: .acceptable, at: start.addingTimeInterval(1_303))
        let forbiddenAfterRecovery = core.handle(classification: .forbidden, at: start.addingTimeInterval(1_304))

        #expect(forbiddenAfterExpiry == .none)
        #expect(acceptableRecovery == .none)
        #expect(forbiddenAfterRecovery == .requestLock)
        #expect(enforcement.requestLockCount == 1)

        let eventKinds = core.readEvents().map(\.kind)
        #expect(eventKinds.contains(.emergencyStarted))
        #expect(eventKinds.contains(.emergencyExtended))
        #expect(eventKinds.contains(.emergencyRefused))
        #expect(eventKinds.contains(.emergencyExpired))
    }

    @Test
    func calibratedClassifierHandlesForbiddenAcceptableUncertainMissingAndRecovery() {
        let classifier = CalibratedProximityClassifier(
            forbiddenThresholdRSSI: -65,
            acceptableThresholdRSSI: -80,
            forbiddenSustain: 2,
            acceptableSustain: 3,
            missingTimeout: 5
        )
        let t0 = Date(timeIntervalSince1970: 50_000)

        #expect(classifier.classify(rssi: -62, at: t0) == .uncertain)
        #expect(classifier.classify(rssi: -61, at: t0.addingTimeInterval(2.1)) == .forbidden)
        #expect(classifier.classify(rssi: -74, at: t0.addingTimeInterval(3)) == .uncertain)
        #expect(classifier.classify(rssi: -84, at: t0.addingTimeInterval(4)) == .uncertain)
        #expect(classifier.classify(rssi: -85, at: t0.addingTimeInterval(7.2)) == .acceptable)

        #expect(classifier.classify(at: t0.addingTimeInterval(13)) == .missing)
        #expect(classifier.classify(rssi: -84, at: t0.addingTimeInterval(14)) == .uncertain)
        #expect(classifier.classify(rssi: -84, at: t0.addingTimeInterval(17.2)) == .acceptable)
    }

    @Test
    func calibratedClassifierConfidenceAndArmedEligibility() {
        let good = CalibratedProximityClassifier.evaluateConfidence(
            forbiddenRSSISamples: [-56, -57, -55, -58, -54],
            acceptableRSSISamples: [-84, -86, -83, -85, -87]
        )
        let weak = CalibratedProximityClassifier.evaluateConfidence(
            forbiddenRSSISamples: [-66, -67, -68, -65],
            acceptableRSSISamples: [-74, -75, -73, -76]
        )
        let unusable = CalibratedProximityClassifier.evaluateConfidence(
            forbiddenRSSISamples: [-71, -72, -70, -73],
            acceptableRSSISamples: [-72, -71, -73, -70]
        )

        #expect(good == .good)
        #expect(weak == .weak)
        #expect(unusable == .unusable)
        #expect(CalibratedProximityClassifier.isArmedEnforcementEligible(confidence: .good))
        #expect(!CalibratedProximityClassifier.isArmedEnforcementEligible(confidence: .weak))
        #expect(!CalibratedProximityClassifier.isArmedEnforcementEligible(confidence: .unusable))
    }

    @Test
    func rpcStatusReturnsJSONRPCResultShape() throws {
        let core = FaradayCore()
        let service = FaradayRPCService(core: core)

        let responseData = service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"faraday.status\"}".utf8))
        #expect(responseData != nil)

        let payload = try #require(responseData).jsonObject()
        #expect(payload["jsonrpc"] as? String == "2.0")
        #expect(payload["id"] as? Int == 1)

        let result = try #require(payload["result"] as? [String: Any])
        #expect(result["sessionState"] as? String == "idle")
        #expect(result["enforcementMode"] as? String == "dryRun")
        #expect(result.keys.contains("calibrationConfidence"))
        #expect(result.keys.contains("overlayState"))
        #expect(result.keys.contains("countdownSeconds"))
    }

    @Test
    func rpcCalibrationEvaluateReturnsConfidenceAndArmedEligibility() throws {
        let core = FaradayCore()
        let service = FaradayRPCService(core: core)

        let request = """
        {"jsonrpc":"2.0","id":13,"method":"calibration.evaluate","params":{"forbiddenRSSISamples":[-55,-56,-57,-54],"acceptableRSSISamples":[-84,-85,-83,-86]}}
        """
        let response = try #require(service.handle(requestData: Data(request.utf8))).jsonObject()
        let result = try #require(response["result"] as? [String: Any])

        #expect(result["confidence"] as? String == "good")
        #expect(result["armedEligible"] as? Bool == true)
        #expect(result["forbiddenMedian"] as? Int == -56)
        #expect(result["acceptableMedian"] as? Int == -85)
        #expect(result["separation"] as? Int == 29)
    }

    @Test
    func ibeaconParserExtractsIdentifierAndRejectsInvalidPayloads() {
        let payload = Data([
            0x4C, 0x00, 0x02, 0x15,
            0x12, 0x34, 0x56, 0x78, 0x12, 0x34, 0x12, 0x34,
            0x12, 0x34, 0x12, 0x34, 0x56, 0x78, 0x90, 0xAB,
            0x00, 0x64, 0x00, 0x07,
            0xC5
        ])

        let parsed = IBeaconParser.parse(manufacturerData: payload)
        #expect(parsed == BeaconIdentifier(
            uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            major: 100,
            minor: 7
        ))

        #expect(IBeaconParser.parse(manufacturerData: Data([0x4C, 0x00, 0x01])) == nil)
    }

    @Test
    func rpcSupportsScanCandidatesManualBeaconSelectionAndLiveRSSI() throws {
        let persistence = InMemoryFaradayPersistence()
        let core = FaradayCore(persistence: persistence)
        let service = FaradayRPCService(core: core)

        let ingestRequest = """
        {"jsonrpc":"2.0","id":1,"method":"beacon.scanIngest","params":{"manufacturerDataHex":"4c000215123456781234123412341234567890ab00640007c5","rssi":-67}}
        """
        let ingestResponse = try #require(service.handle(requestData: Data(ingestRequest.utf8))).jsonObject()
        #expect((ingestResponse["result"] as? [String: Any])?["accepted"] as? Bool == true)

        let candidatesResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"beacon.scanCandidates\"}".utf8))).jsonObject()
        let candidates = try #require((candidatesResponse["result"] as? [String: Any])?["candidates"] as? [[String: Any]])
        #expect(candidates.count == 1)
        #expect(candidates.first?["major"] as? Int == 100)
        #expect(candidates.first?["minor"] as? Int == 7)

        let selectResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"beacon.select\",\"params\":{\"uuid\":\"12345678-1234-1234-1234-1234567890AB\",\"major\":100,\"minor\":7}}".utf8))).jsonObject()
        #expect((selectResponse["result"] as? [String: Any])?["saved"] as? Bool == true)
        #expect(persistence.loadSettings()?.beacon == BeaconIdentifier(
            uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!,
            major: 100,
            minor: 7
        ))

        _ = service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"beacon.scanIngest\",\"params\":{\"manufacturerDataHex\":\"4c000215123456781234123412341234567890ab00640007c5\",\"rssi\":-80}}".utf8))
        _ = service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"beacon.scanIngest\",\"params\":{\"manufacturerDataHex\":\"4c000215123456781234123412341234567890ab00640007c5\",\"rssi\":-62}}".utf8))

        let liveResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"beacon.liveRSSI\"}".utf8))).jsonObject()
        let liveResult = try #require(liveResponse["result"] as? [String: Any])
        #expect(liveResult["selected"] as? Bool == true)
        let samples = try #require(liveResult["samples"] as? [[String: Any]])
        #expect(samples.count == 2)
        #expect(samples.last?["rssi"] as? Int == -62)
    }

    @Test
    func rpcReturnsMethodNotFoundAndSupportsEventTailing() throws {
        let persistence = InMemoryFaradayPersistence()
        let core = FaradayCore(persistence: persistence)
        let service = FaradayRPCService(core: core)

        _ = core.startSession(classification: .forbidden, at: Date(timeIntervalSince1970: 100))
        _ = core.stopSession(at: Date(timeIntervalSince1970: 101))

        let unknownResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"bogus.method\"}".utf8))).jsonObject()
        let unknownError = try #require(unknownResponse["error"] as? [String: Any])
        #expect(unknownError["code"] as? Int == -32601)

        let tailResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"events.tail\",\"params\":{\"afterIndex\":0}}".utf8))).jsonObject()
        let tailResult = try #require(tailResponse["result"] as? [String: Any])
        let events = try #require(tailResult["events"] as? [[String: Any]])
        #expect(events.count == 1)
        #expect(events.first?["kind"] as? String == "sessionEnded")
    }

    @Test
    func rpcSupportsLaunchAgentInstallRestartRemoveAndStatus() throws {
        let core = FaradayCore()
        let launchAgent = SpyLaunchAgentController()
        let service = FaradayRPCService(core: core, launchAgentController: launchAgent)

        let installResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"launchAgent.install\"}".utf8))).jsonObject()
        #expect((installResponse["result"] as? [String: Any])?["ok"] as? Bool == true)

        let restartResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":22,\"method\":\"launchAgent.restart\"}".utf8))).jsonObject()
        #expect((restartResponse["result"] as? [String: Any])?["ok"] as? Bool == true)

        let removeResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":23,\"method\":\"launchAgent.remove\"}".utf8))).jsonObject()
        #expect((removeResponse["result"] as? [String: Any])?["ok"] as? Bool == true)

        let statusResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":24,\"method\":\"launchAgent.status\"}".utf8))).jsonObject()
        let statusResult = try #require(statusResponse["result"] as? [String: Any])
        #expect(statusResult["installed"] as? Bool == true)
        #expect(statusResult["loaded"] as? Bool == false)

        #expect(launchAgent.installs == 1)
        #expect(launchAgent.restarts == 1)
        #expect(launchAgent.removes == 1)
    }

    @Test
    func simulationInjectionMarksStatusAndUsesCoreSessionPath() {
        let enforcement = SpyEnforcementAdapter()
        let core = FaradayCore(enforcement: enforcement)

        let start = core.simulateInjection(.forbidden, at: Date(timeIntervalSince1970: 60_000))
        let activate = core.simulateInjection(.acceptable, at: Date(timeIntervalSince1970: 60_001))
        let violate = core.simulateInjection(.forbidden, at: Date(timeIntervalSince1970: 60_002))

        #expect(start == .none)
        #expect(activate == .beginSession)
        #expect(violate == .requestLock)
        #expect(core.readStatus().observationSource == .simulation)
        #expect(enforcement.requestLockCount == 0)
        #expect(core.readEvents().map(\.kind).contains(.dryRunLockSkipped))
    }

    @Test
    func simulationReplaySupportsViolationAndMissingDegradedScenarios() {
        let core = FaradayCore(
            sessionStateMachine: FocusSessionStateMachine(missingBeaconGracePeriod: 5),
            persistence: InMemoryFaradayPersistence()
        )

        let dryRun = core.replaySimulationScenario(.startActivationViolationDryRun, at: Date(timeIntervalSince1970: 70_000))
        #expect(dryRun.commands == [.none, .beginSession, .requestLock])

        let missing = core.replaySimulationScenario(.missingDegraded, at: Date(timeIntervalSince1970: 80_000))
        #expect(missing.commands == [.none, .beginSession, .none, .none])
        #expect(core.readStatus().observationSource == .simulation)
    }

    @Test
    func rpcSimulationMethodsInjectReplayAndExposeSourceInStatus() throws {
        let core = FaradayCore()
        let service = FaradayRPCService(core: core)

        let injectResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"simulation.inject\",\"params\":{\"classification\":\"forbidden\"}}".utf8))).jsonObject()
        let injectResult = try #require(injectResponse["result"] as? [String: Any])
        #expect(injectResult["command"] as? String == "none")

        let replayResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"simulation.replay\",\"params\":{\"scenario\":\"missingDegraded\"}}".utf8))).jsonObject()
        let replayResult = try #require(replayResponse["result"] as? [String: Any])
        let commands = try #require(replayResult["commands"] as? [String])
        #expect(commands == ["none", "beginSession", "none", "none"])

        let statusResponse = try #require(service.handle(requestData: Data("{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"faraday.status\"}".utf8))).jsonObject()
        let statusResult = try #require(statusResponse["result"] as? [String: Any])
        #expect(statusResult["observationSource"] as? String == "simulation")
    }

    @Test
    func jsonPersistenceRoundTripsSettingsAndUsesJSONLEvents() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = JSONFaradayPersistence(baseDirectoryURL: tempDirectory)
        let beacon = BeaconIdentifier(uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!, major: 1, minor: 2)
        let settings = FaradaySettings(beacon: beacon, forbiddenThresholdRSSI: -65, acceptableThresholdRSSI: -80)
        let t0 = Date(timeIntervalSince1970: 30_000)
        let t1 = t0.addingTimeInterval(1)

        store.saveSettings(settings)
        store.appendEvent(FaradayEvent(timestamp: t0, kind: .sessionBegan))
        store.appendEvent(FaradayEvent(timestamp: t1, kind: .lockRequested))

        #expect(store.loadSettings() == settings)
        #expect(store.loadEvents() == [
            FaradayEvent(timestamp: t0, kind: .sessionBegan),
            FaradayEvent(timestamp: t1, kind: .lockRequested)
        ])

        let eventsJSONLURL = tempDirectory.appendingPathComponent("events.jsonl")
        let rawEvents = try String(contentsOf: eventsJSONLURL, encoding: .utf8)
        let lines = rawEvents.split(separator: "\n")
        #expect(lines.count == 2)
    }
}

final class SpyEnforcementAdapter: EnforcementAdapting {
    private(set) var requestLockCount = 0

    func requestLock() {
        requestLockCount += 1
    }
}

final class SpyOverlayAdapter: OverlayAdapting {
    enum Event: Equatable {
        case showViolation
        case showDegradedBeaconTrust
        case hide
    }

    private(set) var events: [Event] = []

    func showViolation() {
        events.append(.showViolation)
    }

    func showDegradedBeaconTrust() {
        events.append(.showDegradedBeaconTrust)
    }

    func hide() {
        events.append(.hide)
    }
}

final class SpyLaunchAgentController: LaunchAgentControlling {
    var installs = 0
    var restarts = 0
    var removes = 0

    func install() throws {
        installs += 1
    }

    func restart() throws {
        restarts += 1
    }

    func remove() throws {
        removes += 1
    }

    func status() throws -> LaunchAgentStatus {
        LaunchAgentStatus(installed: true, loaded: false)
    }
}

private func armForTests(_ core: FaradayCore) {
    core.saveSettings(FaradaySettings(
        beacon: BeaconIdentifier(uuid: UUID(uuidString: "12345678-1234-1234-1234-1234567890AB")!, major: 1, minor: 2),
        forbiddenThresholdRSSI: -65,
        acceptableThresholdRSSI: -80
    ))
    core.saveCalibration(FaradayCalibration(
        deskRSSI: [-56, -57, -55, -58],
        doorwayRSSI: [-84, -85, -83, -86],
        targetRoomRSSI: []
    ))
    core.setEnforcementMode(.armed)
}

private extension Data {
    func jsonObject() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: self)
        guard let dictionary = object as? [String: Any] else {
            throw NSError(domain: "FaradayCoreTests", code: 1)
        }
        return dictionary
    }
}
