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
}

final class SpyEnforcementAdapter: EnforcementAdapting {
    private(set) var requestLockCount = 0

    func requestLock() {
        requestLockCount += 1
    }
}
