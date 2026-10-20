import CoreGraphics
import ShortcutCore
import XCTest

@testable import KeyboardShortcutter

final class InputSourceSwitchingTests: XCTestCase {
    @MainActor
    func testHiraganaSelectsWithoutPostingKeyboardEvents() async throws {
        let harness = Harness()
        try await harness.select(Harness.hiraganaID).get()

        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID])
        XCTAssertTrue(harness.posted.isEmpty, "Changing the input source must not send a key to the app")
    }

    @MainActor
    func testRepeatedHiraganaSelectionNeverPostsKeyboardEvents() async throws {
        let harness = Harness()
        harness.sources.selectedID = Harness.hiraganaID
        for _ in 0..<2 {
            try await harness.select(Harness.hiraganaID).get()
        }
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID, Harness.hiraganaID])
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testAllModeMetadataUsesExactSelectionWithoutKeyboardEvents() async throws {
        let harness = Harness()
        harness.allowed = false
        let modes: [String?] = [
            nil, "com.apple.inputmethod.Japanese", "com.apple.inputmethod.Japanese.Hiragana",
            "com.apple.inputmethod.Japanese.Katakana", "com.apple.inputmethod.Roman", "another.mode",
        ]
        for mode in modes {
            harness.sources.available = [
                .init(id: "another.ime", name: "ローカライズ名", languages: ["ja"], inputModeID: mode)
            ]
            try await harness.select("another.ime").get()
        }
        XCTAssertTrue(harness.posted.isEmpty)
        XCTAssertEqual(harness.sources.selections, Array(repeating: "another.ime", count: modes.count))
    }

    @MainActor
    func testEnglishSelectionDoesNotRequirePostingPermission() async throws {
        let harness = Harness()
        harness.allowed = false
        try await harness.select(Harness.abcID).get()
        XCTAssertEqual(harness.sources.selections, [Harness.abcID])
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testMissingSourceDoesNotSelectOrPost() async {
        let harness = Harness()
        let result = await harness.select("missing.source")
        guard case .failure(InputSourceService.Failure.missingSource) = result else {
            return XCTFail("An unavailable source must fail")
        }
        XCTAssertTrue(harness.sources.selections.isEmpty)
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testHiraganaSelectionDoesNotRequirePostingPermission() async throws {
        let harness = Harness()
        harness.allowed = false
        try await harness.select(Harness.hiraganaID).get()
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID])
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testFailedTISSelectionNeverPostsKeyboardEvents() async {
        let harness = Harness()
        harness.sources.shouldFail = true
        let result = await harness.select(Harness.hiraganaID)
        guard case .failure = result else { return XCTFail("Expected selection failure") }
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testSelectionWaitsForPhysicalModifierRelease() async {
        for id in [Harness.hiraganaID, Harness.abcID] {
            let harness = Harness()
            harness.modifiers = .option
            let completed = expectation(description: "Released trigger selects the requested source")
            harness.execute(id) { result in
                if case .failure(let error) = result { XCTFail(error.localizedDescription) }
                completed.fulfill()
            }
            await drainMainQueue()
            XCTAssertTrue(harness.sources.selections.isEmpty)
            XCTAssertTrue(harness.posted.isEmpty)
            harness.modifiers = []
            harness.executor.observe(KeyboardEvent(kind: .modifierUp, keyCode: 61))
            await fulfillment(of: [completed], timeout: 1)
            XCTAssertEqual(harness.sources.selections, [id])
            XCTAssertTrue(harness.posted.isEmpty)
        }
    }

    @MainActor
    func testHeldFunctionKeyDelaysSelectionUntilItsRelease() async {
        let harness = Harness()
        harness.heldKeys = [101]
        let completed = expectation(description: "F-key release selects the requested source")
        harness.execute(Harness.hiraganaID) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            completed.fulfill()
        }
        await drainMainQueue()
        XCTAssertTrue(harness.sources.selections.isEmpty)
        harness.heldKeys = []
        harness.executor.observe(KeyboardEvent(kind: .keyUp, keyCode: 101))
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID])
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testChangingTheFrontmostAppCancelsBeforeSelection() async {
        let harness = Harness()
        harness.modifiers = .option
        let completed = expectation(description: "Focus change cancels pending selection")
        harness.execute(Harness.hiraganaID) { result in
            guard case .failure = result else { return XCTFail("Expected cancellation") }
            completed.fulfill()
        }
        await drainMainQueue()
        harness.pid = 2
        harness.modifiers = []
        harness.executor.observe(KeyboardEvent(kind: .modifierUp, keyCode: 61))
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertTrue(harness.sources.selections.isEmpty)
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testPostingPermissionRevokedWhileWaitingDoesNotPreventSelection() async {
        let harness = Harness()
        harness.modifiers = .option
        let completed = expectation(description: "Selection does not need posting permission")
        harness.execute(Harness.hiraganaID) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            completed.fulfill()
        }
        await drainMainQueue()
        harness.allowed = false
        harness.modifiers = []
        harness.executor.observe(KeyboardEvent(kind: .modifierUp, keyCode: 61))
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID])
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testLaterEnglishRequestCancelsPendingJapaneseSwitch() async throws {
        let harness = Harness()
        harness.modifiers = .option
        let canceled = expectation(description: "Superseded Japanese selection is canceled")
        harness.execute(Harness.hiraganaID) { result in
            guard case .failure = result else { return XCTFail("Expected cancellation") }
            canceled.fulfill()
        }
        await drainMainQueue()
        let englishSelected = expectation(description: "Latest English selection completes")
        harness.execute(Harness.abcID) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            englishSelected.fulfill()
        }
        await drainMainQueue()
        await fulfillment(of: [canceled], timeout: 1)
        XCTAssertTrue(harness.sources.selections.isEmpty)
        harness.modifiers = []
        harness.executor.observe(KeyboardEvent(kind: .modifierUp, keyCode: 61))
        await fulfillment(of: [englishSelected], timeout: 1)
        await drainMainQueue()
        XCTAssertEqual(harness.sources.selections, [Harness.abcID])
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testResetAndNewTypingCancelPendingSelectionWithoutChangingTheSource() async {
        for interruption in [
            KeyboardEvent(kind: .reset), KeyboardEvent(kind: .keyDown, keyCode: 0),
            KeyboardEvent(kind: .mouseActivity), KeyboardEvent(kind: .modifierDown, keyCode: 56),
        ] {
            let harness = Harness()
            harness.modifiers = .option
            let canceled = expectation(description: "Interrupted selection is canceled")
            harness.execute(Harness.hiraganaID) { result in
                guard case .failure = result else { return XCTFail("Expected cancellation") }
                canceled.fulfill()
            }
            await drainMainQueue()
            harness.executor.observe(interruption)
            await fulfillment(of: [canceled], timeout: 1)
            XCTAssertTrue(harness.sources.selections.isEmpty)
            XCTAssertTrue(harness.posted.isEmpty)
        }
    }

    @MainActor
    func testLostKeyReleaseRecoveryCancelsOldSelectionAndAllowsTheNextOptionTap() async throws {
        let harness = Harness()
        let rule = ShortcutRule(
            name: "Right Option", trigger: .modifierTap(.rightOption),
            action: ShortcutAction(kind: "inputSource", inputSourceID: Harness.hiraganaID))
        var matcher = TriggerMatcher()
        var now: TimeInterval = 10
        var hardwareReleased = false
        let selected = expectation(description: "A fresh Option tap selects after recovery")
        let monitor = EventMonitor(
            onEvent: { event in
                harness.executor.observe(event)
                for matched in matcher.process(event, rules: [rule]) {
                    harness.executor.execute(matched.action) { result in
                        if case .failure(let error) = result { XCTFail(error.localizedDescription) }
                        selected.fulfill()
                    }
                }
                return false
            }, onStatusChange: { _ in }, uptime: { now },
            hardwareKeysAreReleased: { hardwareReleased }, currentEventTimestamp: { 200 },
            secureInputEnabled: { false }, mouseButtonIsDown: { false })

        let lostReleasePress = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true))
        lostReleasePress.timestamp = 100
        _ = monitor.receive(type: .keyDown, event: lostReleasePress)

        let canceled = expectation(description: "Recovery cancels the blocked source request")
        harness.execute(Harness.abcID) { result in
            guard case .failure = result else { return XCTFail("Expected cancellation") }
            canceled.fulfill()
        }
        await drainMainQueue()
        XCTAssertTrue(harness.sources.selections.isEmpty)

        // The physical key was released without a corresponding event reaching the app.
        hardwareReleased = true
        now = 11
        monitor.repairStaleHeldState()
        await fulfillment(of: [canceled], timeout: 1)
        XCTAssertTrue(harness.sources.selections.isEmpty, "Recovery must not run the old request")

        let optionDown = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 61, keyDown: true))
        optionDown.flags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)
        optionDown.timestamp = 201
        _ = monitor.receive(type: .flagsChanged, event: optionDown)
        let optionUp = try XCTUnwrap(
            CGEvent(keyboardEventSource: nil, virtualKey: 61, keyDown: false))
        optionUp.flags = []
        optionUp.timestamp = 202
        _ = monitor.receive(type: .flagsChanged, event: optionUp)
        await fulfillment(of: [selected], timeout: 1)

        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID])
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testShortcutSendingStillRequiresPostingPermission() async {
        let harness = Harness()
        harness.allowed = false
        let completed = expectation(description: "Shortcut permission failure is reported")
        harness.executor.execute(
            ShortcutAction(kind: "sendShortcut", shortcut: KeyCombination(keyCode: 40, modifiers: .command))
        ) { result in
            defer { completed.fulfill() }
            guard case .failure = result else { return XCTFail("Expected permission failure") }
        }
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertTrue(harness.posted.isEmpty)
        XCTAssertTrue(harness.sources.selections.isEmpty)
    }

    @MainActor
    func testShortcutSendingWaitsForReleaseThenPostsBalancedEvents() async {
        let harness = Harness()
        harness.modifiers = .option
        harness.heldKeys = [101]
        harness.executor.observe(KeyboardEvent(kind: .keyDown, keyCode: 101))
        let completed = expectation(description: "Shortcut is sent after the trigger releases")
        harness.executor.execute(
            ShortcutAction(kind: "sendShortcut", shortcut: KeyCombination(keyCode: 40, modifiers: .command))
        ) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            completed.fulfill()
        }
        await drainMainQueue()
        XCTAssertTrue(harness.posted.isEmpty)
        harness.modifiers = []
        harness.executor.observe(KeyboardEvent(kind: .modifierUp, keyCode: 61))
        await drainMainQueue()
        XCTAssertTrue(harness.posted.isEmpty)
        harness.heldKeys = []
        harness.executor.observe(KeyboardEvent(kind: .keyUp, keyCode: 101))
        await fulfillment(of: [completed], timeout: 1)

        XCTAssertEqual(harness.posted.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(
            harness.posted.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [55, 40, 40, 55])
        XCTAssertEqual(harness.posted.map(\.flags), [.maskCommand, .maskCommand, .maskCommand, []])
        for event in harness.posted {
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), shortcutterSyntheticEventTag)
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 0)
        }
        XCTAssertTrue(harness.sources.selections.isEmpty)
    }

    @MainActor
    func testShortcutSendingRechecksPermissionAfterWaiting() async {
        let harness = Harness()
        harness.modifiers = .option
        let completed = expectation(description: "Revoked posting permission prevents the shortcut")
        harness.executor.execute(
            ShortcutAction(kind: "sendShortcut", shortcut: KeyCombination(keyCode: 40, modifiers: .command))
        ) { result in
            defer { completed.fulfill() }
            guard case .failure = result else { return XCTFail("Expected permission failure") }
        }
        await drainMainQueue()
        XCTAssertTrue(harness.posted.isEmpty)
        harness.allowed = false
        harness.modifiers = []
        harness.executor.observe(KeyboardEvent(kind: .modifierUp, keyCode: 61))
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertTrue(harness.posted.isEmpty)
        XCTAssertTrue(harness.sources.selections.isEmpty)
    }

    @MainActor
    func testUnconfirmedHiraganaSwitchReselectsASCIIThenSendsOnlyKana() async throws {
        let harness = Harness()
        harness.sources.selectedID = Harness.abcID
        try await harness.select(Harness.hiraganaID).get()
        // Only this app's own selection is announced; the focused client never answers.
        harness.recovery.selectedSourceDidChange()
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID])
        XCTAssertTrue(harness.posted.isEmpty)

        harness.runScheduled()
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID, Harness.abcID])
        XCTAssertTrue(harness.posted.isEmpty, "Kana must wait until the client can apply ASCII")

        harness.runScheduled()
        XCTAssertEqual(harness.posted.map(\.type), [.keyDown, .keyUp])
        for event in harness.posted {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 104)
            XCTAssertEqual(event.flags, [])
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), shortcutterSyntheticEventTag)
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 0)
        }
        XCTAssertNil(harness.recovery.pendingTargetID)
        XCTAssertTrue(harness.scheduled.isEmpty)
    }

    @MainActor
    func testConfirmedHiraganaSwitchNeverReselectsOrSendsKeys() async throws {
        let harness = Harness()
        harness.sources.selectedID = Harness.abcID
        try await harness.select(Harness.hiraganaID).get()
        harness.recovery.selectedSourceDidChange()
        harness.recovery.selectedSourceDidChange()
        XCTAssertNil(harness.recovery.pendingTargetID)
        harness.runScheduled()
        harness.runScheduled()
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID])
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testRecoveryOnlyCoversSwitchingFromAnASCIILayoutToAppleHiragana() async throws {
        let katakana = InputSourceService.Source(
            id: "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese.Katakana", name: "カタカナ",
            languages: ["ja"], inputModeID: "com.apple.inputmethod.Japanese.Katakana")
        let otherJapanese = InputSourceService.Source(
            id: "com.example.inputmethod.Japanese", name: "日本語", languages: ["ja"],
            inputModeID: "com.apple.inputmethod.Japanese")
        let russian = InputSourceService.Source(
            id: "com.apple.keylayout.Russian", name: "Russian", languages: ["ru"])
        let cases: [(previous: String?, target: String)] = [
            (Harness.hiraganaID, Harness.hiraganaID), (nil, Harness.hiraganaID),
            (russian.id, Harness.hiraganaID), (Harness.abcID, katakana.id),
            (Harness.abcID, otherJapanese.id), (Harness.hiraganaID, Harness.abcID),
        ]
        for (previous, target) in cases {
            let harness = Harness()
            harness.sources.available += [katakana, otherJapanese, russian]
            harness.sources.selectedID = previous
            try await harness.select(target).get()
            let name = "\(previous ?? "none") -> \(target)"
            XCTAssertNil(harness.recovery.pendingTargetID, name)
            XCTAssertTrue(harness.scheduled.isEmpty, name)
            XCTAssertEqual(harness.sources.selections, [target], name)
            XCTAssertTrue(harness.posted.isEmpty, name)
        }
    }

    @MainActor
    func testRecoveryDoesNothingWhenStateChangesBeforeTheDeadline() async throws {
        let interruptions: [(String, (Harness) -> Void)] = [
            ("frontmost app", { $0.pid = 2 }), ("source", { $0.sources.selectedID = Harness.abcID }),
            ("secure input", { $0.secureInput = true }), ("held modifier", { $0.modifiers = .command }),
            ("permission", { $0.allowed = false }),
            ("reset", { $0.executor.observe(KeyboardEvent(kind: .reset)) }),
            ("pause", { $0.executor.cancelPendingAction() }),
        ]
        for (name, interrupt) in interruptions {
            let harness = Harness()
            harness.sources.selectedID = Harness.abcID
            try await harness.select(Harness.hiraganaID).get()
            interrupt(harness)
            harness.runScheduled()
            harness.runScheduled()
            XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID], name)
            XCTAssertTrue(harness.posted.isEmpty, name)
            XCTAssertNil(harness.recovery.pendingTargetID, name)
        }
    }

    @MainActor
    func testKanaIsNotSentWhenInterruptedAfterReselectingASCII() async throws {
        let interruptions: [(String, (Harness) -> Void)] = [
            ("frontmost app", { $0.pid = 2 }), ("source", { $0.sources.selectedID = Harness.hiraganaID }),
            ("secure input", { $0.secureInput = true }), ("held modifier", { $0.modifiers = .shift }),
            ("permission", { $0.allowed = false }),
            ("reset", { $0.executor.observe(KeyboardEvent(kind: .reset)) }),
        ]
        for (name, interrupt) in interruptions {
            let harness = Harness()
            harness.sources.selectedID = Harness.abcID
            try await harness.select(Harness.hiraganaID).get()
            harness.runScheduled()
            XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID, Harness.abcID], name)
            interrupt(harness)
            harness.runScheduled()
            XCTAssertTrue(harness.posted.isEmpty, name)
            XCTAssertNil(harness.recovery.pendingTargetID, name)
        }
    }

    @MainActor
    func testFailedASCIIReselectionNeverSendsKana() async throws {
        let harness = Harness()
        harness.sources.selectedID = Harness.abcID
        try await harness.select(Harness.hiraganaID).get()
        harness.sources.shouldFail = true
        harness.runScheduled()
        harness.runScheduled()
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID])
        XCTAssertTrue(harness.posted.isEmpty)
        XCTAssertNil(harness.recovery.pendingTargetID)
    }

    @MainActor
    func testRepeatedHiraganaRequestJoinsTheRunningCheckWithoutReselecting() async throws {
        let harness = Harness()
        harness.sources.selectedID = Harness.abcID
        try await harness.select(Harness.hiraganaID).get()
        try await harness.select(Harness.hiraganaID).get()
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID], "No rapid second TIS change")

        harness.runScheduled()
        try await harness.select(Harness.hiraganaID).get()
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID, Harness.abcID])

        harness.runScheduled()
        XCTAssertEqual(harness.posted.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [104, 104])
        XCTAssertTrue(harness.scheduled.isEmpty)
    }

    @MainActor
    func testEnglishRequestCancelsTheJapaneseRecoveryAtEitherStage() async throws {
        for reselectASCIIFirst in [false, true] {
            let harness = Harness()
            harness.sources.selectedID = Harness.abcID
            try await harness.select(Harness.hiraganaID).get()
            if reselectASCIIFirst { harness.runScheduled() }
            try await harness.select(Harness.abcID).get()
            harness.runScheduled()
            harness.runScheduled()
            XCTAssertEqual(harness.sources.selections.last, Harness.abcID)
            XCTAssertEqual(harness.sources.selections.filter { $0 == Harness.hiraganaID }.count, 1)
            XCTAssertTrue(harness.posted.isEmpty)
            XCTAssertNil(harness.recovery.pendingTargetID)
        }
    }

    @MainActor
    private func drainMainQueue() async {
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    @MainActor
    private final class Harness {
        static let hiraganaID = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
        static let abcID = "com.apple.keylayout.ABC"
        let sources = Sources()
        var allowed = true
        var modifiers: KeyModifiers = []
        var heldKeys: Set<UInt16> = []
        var pid: pid_t = 1
        var secureInput = false
        var posted: [CGEvent] = []
        var scheduled: [@MainActor () -> Void] = []
        lazy var sender = SendShortcutActionHandler(
            permissionGranted: { [unowned self] in allowed },
            physicalModifiers: { [unowned self] in modifiers },
            heldKeyCodes: { [unowned self] in heldKeys },
            frontmostPID: { [unowned self] in pid },
            postEvent: { [unowned self] in posted.append($0) })
        lazy var recovery = InputMethodActivationRecovery(
            service: sources, observesSystemNotifications: false,
            permissionGranted: { [unowned self] in allowed },
            physicalModifiers: { [unowned self] in modifiers },
            frontmostPID: { [unowned self] in pid },
            secureInputEnabled: { [unowned self] in secureInput },
            postEvent: { [unowned self] in posted.append($0) },
            schedule: { [unowned self] _, work in scheduled.append(work) })
        lazy var executor = ActionExecutor(
            inputSourceService: sources, shortcutHandler: sender, activationRecovery: recovery)

        func execute(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
            executor.execute(ShortcutAction(kind: "inputSource", inputSourceID: id), completion: completion)
        }

        func select(_ id: String) async -> Result<Void, Error> {
            await withCheckedContinuation { continuation in
                execute(id) { continuation.resume(returning: $0) }
            }
        }

        /// Runs the recovery's delayed steps that are due, as their timers would.
        func runScheduled() {
            let work = scheduled
            scheduled.removeAll()
            for step in work { step() }
        }
    }

    @MainActor
    private final class Sources: InputSourceSelecting {
        var available: [InputSourceService.Source] = [
            .init(
                id: Harness.hiraganaID, name: "ひらがな", languages: ["ja"],
                inputModeID: "com.apple.inputmethod.Japanese"),
            .init(id: Harness.abcID, name: "ABC", languages: ["en"], isASCIICapableLayout: true),
        ]
        var selectedID: String?
        var selections: [String] = []
        var shouldFail = false

        func enumerate() -> [InputSourceService.Source] { available }

        func select(id: String) throws {
            if shouldFail { throw InputSourceService.Failure.selectionFailed(id, -50) }
            selections.append(id)
            selectedID = id
        }

        func currentSourceID() -> String? { selectedID }
    }
}
