import CoreGraphics
import ShortcutCore
import XCTest

@testable import KeyboardShortcutter

final class EventMonitorRecoveryTests: XCTestCase {
    @MainActor
    private final class Harness {
        var now: TimeInterval = 10
        var hardwareReleased = true
        var secureInput = false
        var timestamp: CGEventTimestamp? = 1_000
        var resetCount = 0
        var fired = 0
        var matcher = TriggerMatcher()
        let rule = ShortcutRule(
            name: "Right Option", trigger: .modifierTap(.rightOption),
            action: ShortcutAction(kind: "inputSource", inputSourceID: "test.source"))

        lazy var monitor = EventMonitor(
            onEvent: { [unowned self] event in
                if event.kind == .reset { resetCount += 1 }
                fired += matcher.process(event, rules: [rule]).count
                return false
            }, onStatusChange: { _ in }, uptime: { [unowned self] in now },
            hardwareKeysAreReleased: { [unowned self] in hardwareReleased },
            currentEventTimestamp: { [unowned self] in timestamp },
            secureInputEnabled: { [unowned self] in secureInput }, mouseButtonIsDown: { false })

        func send(
            _ type: CGEventType, code: UInt16 = 0, flags: CGEventFlags = [],
            timestamp: CGEventTimestamp = 100, isRepeat: Bool = false
        ) throws {
            let event = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true))
            event.type = type
            event.flags = flags
            event.timestamp = timestamp
            event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
            _ = monitor.receive(type: type, event: event)
        }

        func rightOptionTap(timestamp: CGEventTimestamp = 2_000) throws {
            try send(
                .flagsChanged, code: 61,
                flags: CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40),
                timestamp: timestamp)
            try send(.flagsChanged, code: 61, timestamp: timestamp + 1)
        }
    }

    @MainActor
    func testMissedOrdinaryKeyReleaseRecoversModifierTapWithoutFiringDuringRepair() throws {
        let h = Harness()
        try h.send(.keyDown, code: 0)
        try h.rightOptionTap(timestamp: 200)
        XCTAssertEqual(h.fired, 0)
        h.now += 1
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 1)
        XCTAssertEqual(h.fired, 0)
        try h.rightOptionTap()
        XCTAssertEqual(h.fired, 1)
    }

    @MainActor
    func testHeldKeysAndRecentRepeatsPreventRepair() throws {
        let h = Harness()
        try h.send(.keyDown)
        h.now += 0.49
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 0)
        h.now += 1
        h.hardwareReleased = false
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 0)
        h.hardwareReleased = true
        try h.send(.keyDown, isRepeat: true)
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 0)
        h.now += 0.5
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 1)
    }

    @MainActor
    func testMouseMotionDoesNotPreventRepairAndCleanIdleStateDoesNotResetAgain() throws {
        let h = Harness()
        try h.send(.keyDown)
        h.now += 1
        try h.send(.mouseMoved)
        h.monitor.repairStaleHeldState()
        h.now += 1
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 1)
    }

    @MainActor
    func testSecureInputAndUnavailableTimestampDoNotRepair() throws {
        let h = Harness()
        try h.send(.keyDown)
        h.now += 1
        h.secureInput = true
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 0)
        h.secureInput = false
        h.timestamp = nil
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 0)
        h.timestamp = 1_000
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 1)
    }

    @MainActor
    func testMissedFunctionModifierReleaseClearsPhysicalFunctionState() throws {
        let h = Harness()
        try h.send(.flagsChanged, code: 63, flags: .maskSecondaryFn)
        h.now += 1
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, 1)
        try h.rightOptionTap()
        XCTAssertEqual(h.fired, 1)
    }

    @MainActor
    func testQueuedKeyboardEventsBeforeRepairCannotFireOrReintroduceHeldState() throws {
        let h = Harness()
        try h.send(.keyDown)
        h.now += 1
        h.monitor.repairStaleHeldState()
        try h.rightOptionTap(timestamp: 900)
        try h.send(.keyDown, code: 1, timestamp: 1_000)
        XCTAssertEqual(h.fired, 0)
        try h.rightOptionTap(timestamp: 1_001)
        XCTAssertEqual(h.fired, 1)
    }

    @MainActor
    func testStopClearsRecoveryState() throws {
        let h = Harness()
        try h.send(.keyDown)
        h.monitor.stop()
        let resetsAfterStop = h.resetCount
        h.now += 1
        h.monitor.repairStaleHeldState()
        XCTAssertEqual(h.resetCount, resetsAfterStop)
    }
}
