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
        var posted: [CGEvent] = []
        lazy var sender = SendShortcutActionHandler(
            permissionGranted: { [unowned self] in allowed },
            physicalModifiers: { [unowned self] in modifiers },
            heldKeyCodes: { [unowned self] in heldKeys },
            frontmostPID: { [unowned self] in pid },
            postEvent: { [unowned self] in posted.append($0) })
        lazy var executor = ActionExecutor(inputSourceService: sources, shortcutHandler: sender)

        func execute(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
            executor.execute(ShortcutAction(kind: "inputSource", inputSourceID: id), completion: completion)
        }

        func select(_ id: String) async -> Result<Void, Error> {
            await withCheckedContinuation { continuation in
                execute(id) { continuation.resume(returning: $0) }
            }
        }
    }

    @MainActor
    private final class Sources: InputSourceSelecting {
        var available: [InputSourceService.Source] = [
            .init(
                id: Harness.hiraganaID, name: "ひらがな", languages: ["ja"],
                inputModeID: "com.apple.inputmethod.Japanese"),
            .init(id: Harness.abcID, name: "ABC", languages: ["en"]),
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
    }
}
