import Testing
@testable import FaradayCore

struct FaradayCoreScaffoldTests {
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
}

final class SpyEnforcementAdapter: EnforcementAdapting {
    private(set) var requestLockCount = 0

    func requestLock() {
        requestLockCount += 1
    }
}
