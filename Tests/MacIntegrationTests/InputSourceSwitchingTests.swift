import CoreGraphics
import ShortcutCore
import XCTest

@testable import KeyboardShortcutter

final class InputSourceSwitchingTests: XCTestCase {
    @MainActor
    func testHiraganaActivatesTheInputClientEvenWhenAlreadySelected() async throws {
        let harness = Harness()
        harness.sources.selectedID = Harness.hiraganaID
        for _ in 0..<2 {
            try await harness.select(Harness.hiraganaID).get()
        }
        XCTAssertEqual(harness.sources.selections, [Harness.hiraganaID, Harness.hiraganaID])
        XCTAssertEqual(harness.posted.map(\.type), [.keyDown, .keyUp, .keyDown, .keyUp])
        for event in harness.posted {
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventKeycode), 104)
            XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 0)
            XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), shortcutterSyntheticEventTag)
            XCTAssertTrue(event.flags.isEmpty, "Kana must not inherit the physical Option modifier")
        }
        XCTAssertEqual(harness.sourceAtPosting, Array(repeating: Harness.hiraganaID, count: 4))
    }

    @MainActor
    func testHiraganaDetectionUsesModeMetadataRatherThanProviderOrLocalizedName() async throws {
        let harness = Harness()
        for mode in ["com.apple.inputmethod.Japanese", "com.apple.inputmethod.Japanese.Hiragana"] {
            harness.sources.available = [
                .init(id: "another.ime", name: "ローカライズ名", languages: ["ja"], inputModeID: mode)
            ]
            try await harness.select("another.ime").get()
        }
        XCTAssertEqual(harness.posted.count, 4)
        XCTAssertEqual(harness.sources.selections, ["another.ime", "another.ime"])
    }

    @MainActor
    func testOtherModesKeepExactSelectionWithoutKanaOrPostingPermission() async throws {
        let harness = Harness()
        harness.allowed = false
        for mode in [nil, "com.apple.inputmethod.Japanese.Katakana", "com.apple.inputmethod.Roman"] {
            harness.sources.available = [
                .init(id: "configured.source", name: "ひらがな", languages: ["ja"], inputModeID: mode)
            ]
            try await harness.select("configured.source").get()
        }
        XCTAssertEqual(harness.sources.selections.count, 3)
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testMissingSourceDoesNotSelectOrSendKana() async {
        let harness = Harness()
        let result = await harness.select("missing.source")
        guard case .failure(InputSourceService.Failure.missingSource) = result else {
            return XCTFail("An unavailable source must fail")
        }
        XCTAssertTrue(harness.sources.selections.isEmpty)
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testDeniedPermissionDoesNotPartiallySwitchTheMenu() async {
        let harness = Harness()
        harness.allowed = false
        let result = await harness.select(Harness.hiraganaID)
        guard case .failure(let error) = result else { return XCTFail("Expected permission failure") }
        XCTAssertTrue(error.localizedDescription.contains("アクセシビリティ"))
        XCTAssertTrue(harness.sources.selections.isEmpty)
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testFailedTISSelectionNeverPostsKanaToADifferentInputMethod() async {
        let harness = Harness()
        harness.sources.shouldFail = true
        let result = await harness.select(Harness.hiraganaID)
        guard case .failure = result else { return XCTFail("Expected selection failure") }
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testBothSelectionAndKanaWaitForPhysicalModifierRelease() async {
        let harness = Harness()
        harness.modifiers = .option
        let completed = expectation(description: "Released trigger delivers Kana")
        harness.execute(Harness.hiraganaID) { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            completed.fulfill()
        }
        await drainMainQueue()
        XCTAssertTrue(harness.sources.selections.isEmpty)
        XCTAssertTrue(harness.posted.isEmpty)
        harness.modifiers = []
        harness.executor.observe(KeyboardEvent(kind: .modifierUp, keyCode: 61))
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(harness.posted.count, 2)
    }

    @MainActor
    func testHeldFunctionKeyDelaysSelectionUntilItsRelease() async {
        let harness = Harness()
        harness.heldKeys = [101]
        let completed = expectation(description: "F-key release delivers Kana")
        harness.execute(Harness.hiraganaID) { _ in completed.fulfill() }
        await drainMainQueue()
        XCTAssertTrue(harness.sources.selections.isEmpty)
        harness.heldKeys = []
        harness.executor.observe(KeyboardEvent(kind: .keyUp, keyCode: 101))
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertEqual(harness.posted.count, 2)
    }

    @MainActor
    func testChangingTheFrontmostAppCancelsBeforeSelection() async {
        let harness = Harness()
        harness.modifiers = .option
        let completed = expectation(description: "Focus change cancels pending Kana")
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
    func testPermissionRevokedWhileWaitingDoesNotSelectOrPost() async {
        let harness = Harness()
        harness.modifiers = .option
        let completed = expectation(description: "Revoked permission fails")
        harness.execute(Harness.hiraganaID) { result in
            guard case .failure = result else { return XCTFail("Expected permission failure") }
            completed.fulfill()
        }
        await drainMainQueue()
        harness.allowed = false
        harness.modifiers = []
        harness.executor.observe(KeyboardEvent(kind: .modifierUp, keyCode: 61))
        await fulfillment(of: [completed], timeout: 1)
        XCTAssertTrue(harness.sources.selections.isEmpty)
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testLaterEnglishRequestCancelsPendingJapaneseSwitch() async throws {
        let harness = Harness()
        harness.modifiers = .option
        let canceled = expectation(description: "Superseded Kana is canceled")
        harness.execute(Harness.hiraganaID) { result in
            guard case .failure = result else { return XCTFail("Expected cancellation") }
            canceled.fulfill()
        }
        await drainMainQueue()
        try await harness.select(Harness.abcID).get()
        harness.modifiers = []
        harness.executor.observe(KeyboardEvent(kind: .modifierUp, keyCode: 61))
        await fulfillment(of: [canceled], timeout: 1)
        await drainMainQueue()
        XCTAssertEqual(harness.sources.selections, [Harness.abcID])
        XCTAssertTrue(harness.posted.isEmpty)
    }

    @MainActor
    func testResetAndNewTypingCancelPendingKanaWithoutChangingTheSource() async {
        for interruption in [
            KeyboardEvent(kind: .reset), KeyboardEvent(kind: .keyDown, keyCode: 0),
            KeyboardEvent(kind: .mouseActivity), KeyboardEvent(kind: .modifierDown, keyCode: 56),
        ] {
            let harness = Harness()
            harness.modifiers = .option
            let canceled = expectation(description: "Interrupted Kana is canceled")
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
        var sourceAtPosting: [String?] = []
        lazy var sender = SendShortcutActionHandler(
            permissionGranted: { [unowned self] in allowed },
            physicalModifiers: { [unowned self] in modifiers },
            heldKeyCodes: { [unowned self] in heldKeys },
            frontmostPID: { [unowned self] in pid },
            postEvent: { [unowned self] in
                posted.append($0)
                sourceAtPosting.append(sources.selectedID)
            })
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
