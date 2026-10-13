import CoreGraphics
import ShortcutCore
import XCTest

@testable import KeyboardShortcutter

final class SystemServicesIntegrationTests: XCTestCase {
    @MainActor
    func testEnumerationProducesUsableUniqueInputSourceDescriptors() async {
        let sources = InputSourceService().enumerate()
        // Empty results are allowed on machines without an interactive login session.
        XCTAssertEqual(Set(sources.map(\.id)).count, sources.count)
        XCTAssertTrue(sources.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
    }

    @MainActor
    func testSelectingDefinitelyMissingSourceFailsWithoutSelectingAnything() async {
        let service = InputSourceService()
        let missingID = "KeyboardShortcutterTests.missing.\(UUID().uuidString)"
        XCTAssertFalse(service.enumerate().contains { $0.id == missingID })
        XCTAssertThrowsError(try service.select(id: missingID)) { error in
            guard case InputSourceService.Failure.missingSource(let identifier) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(identifier, missingID)
        }
    }

    @MainActor
    func testUnknownActionFailsAsynchronously() async {
        let executor = ActionExecutor(inputSourceService: InputSourceService())
        var executionReturned = false
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            executor.execute(ShortcutAction(kind: "unavailableFutureAction")) { result in
                XCTAssertTrue(executionReturned, "The executor must defer work out of the event callback")
                continuation.resume(returning: result)
            }
            executionReturned = true
        }
        switch result {
        case .success: XCTFail("Unknown actions must fail")
        case .failure(let error): XCTAssertTrue(error.localizedDescription.contains("not supported"))
        }
    }

    @MainActor
    func testCancelPendingExecutionPreventsQueuedActionFromRunning() async {
        let executor = ActionExecutor(inputSourceService: InputSourceService())
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            executor.execute(ShortcutAction(kind: "unavailableFutureAction")) {
                continuation.resume(returning: $0)
            }
            executor.cancelPendingAction()
        }
        switch result {
        case .success: XCTFail("Canceled actions must fail")
        case .failure(let error): XCTAssertTrue(error.localizedDescription.contains("canceled"))
        }
    }

    @MainActor
    func testEventResetInvalidatesQueuedExecution() async {
        let executor = ActionExecutor(inputSourceService: InputSourceService())
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            executor.execute(ShortcutAction(kind: "unavailableFutureAction")) {
                continuation.resume(returning: $0)
            }
            executor.observe(KeyboardEvent(kind: .reset))
        }
        switch result {
        case .success: XCTFail("Actions queued before reset must fail")
        case .failure(let error): XCTAssertTrue(error.localizedDescription.contains("canceled"))
        }
    }

    @MainActor
    func testEventFlagTranslationIgnoresCapsLockAndDeviceSideBits() async {
        let allLogical: CGEventFlags = [
            .maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn,
        ]
        XCTAssertEqual(
            EventMonitor.modifiers(from: allLogical), [.control, .option, .shift, .command, .function])
        XCTAssertEqual(EventMonitor.modifiers(from: [.maskAlphaShift, .maskNumericPad]), [])
        let leftOptionAndRightOption = CGEventFlags(
            rawValue: 0x20 | 0x40 | CGEventFlags.maskAlternate.rawValue)
        XCTAssertEqual(EventMonitor.modifiers(from: leftOptionAndRightOption), .option)
    }

    @MainActor
    func testArrowAndFKeyIntrinsicFunctionFlagDoesNotRequirePhysicalFnModifier() async {
        // AppKit can set the function bit for navigation/F keys even when Fn is up.
        let flags: CGEventFlags = [.maskCommand, .maskSecondaryFn]
        XCTAssertEqual(
            EventMonitor.modifiers(from: flags, physicalFunctionDown: false), .command)
    }

    @MainActor
    func testArrowAndFKeyFlagsRetainFnWhenPhysicalFunctionKeyIsHeld() async {
        let flags: CGEventFlags = [.maskCommand, .maskSecondaryFn]
        XCTAssertEqual(
            EventMonitor.modifiers(from: flags, physicalFunctionDown: true), [.command, .function])
    }

    @MainActor
    func testPhysicalFunctionKeyStateAddsFnWhenRawEventFlagIsMissing() async {
        XCTAssertEqual(
            EventMonitor.modifiers(from: .maskCommand, physicalFunctionDown: true),
            [.command, .function])
    }

    @MainActor
    func testUnspecifiedPhysicalFunctionStatePreservesRawFunctionFlag() async {
        XCTAssertEqual(
            EventMonitor.modifiers(from: [.maskCommand, .maskSecondaryFn], physicalFunctionDown: nil),
            [.command, .function])
    }
}
