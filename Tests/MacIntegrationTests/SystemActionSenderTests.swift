import AppKit
import CoreGraphics
import ShortcutCore
import XCTest

@testable import KeyboardShortcutter

final class SystemActionSenderTests: XCTestCase {
    @MainActor
    func testEachSystemControlCreatesTaggedBalancedMediaKeyEventsWithoutPosting() throws {
        // Expected public IOKit NX key types, independently checked against ev_keymap.h.
        let controls: [(SystemAction, Int)] = [
            (.volumeUp, 0), (.volumeDown, 1), (.brightnessUp, 2), (.brightnessDown, 3),
            (.mute, 7), (.playPause, 16), (.nextTrack, 17), (.previousTrack, 18),
        ]
        for (action, keyType) in controls {
            var posted: [CGEvent] = []
            let sender = SystemActionSender(permissionGranted: { true }, postEvent: { posted.append($0) })
            try sender.send(action)
            XCTAssertEqual(posted.count, 2)
            for (index, cgEvent) in posted.enumerated() {
                let event = try XCTUnwrap(NSEvent(cgEvent: cgEvent))
                XCTAssertEqual(event.type, .systemDefined)
                XCTAssertEqual(event.subtype.rawValue, 8)
                XCTAssertEqual(event.data1 >> 16, keyType)
                XCTAssertEqual((event.data1 >> 8) & 0xff, index == 0 ? 10 : 11)
                XCTAssertEqual(event.data1 & 0xff, 0, "No native held-key repeat remains active")
                XCTAssertEqual(event.data2, -1)
                XCTAssertEqual(
                    cgEvent.getIntegerValueField(.eventSourceUserData), shortcutterSyntheticEventTag)
                XCTAssertTrue(
                    event.modifierFlags.intersection([.shift, .control, .option, .command, .function]).isEmpty
                )
            }
        }
    }

    @MainActor
    func testPermissionFailureNeverAllocatesOrPostsMediaEvents() {
        var allocated = false
        var posted = false
        let sender = SystemActionSender(
            permissionGranted: { false },
            makeEvent: { _, _ in
                allocated = true; return nil
            }, postEvent: { _ in posted = true })
        XCTAssertThrowsError(try sender.send(.volumeDown)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Accessibility"))
        }
        XCTAssertFalse(allocated)
        XCTAssertFalse(posted)
    }

    @MainActor
    func testFailedReleaseAllocationCannotLeaveAKeyPressed() {
        var posted = false
        let sender = SystemActionSender(
            permissionGranted: { true },
            makeEvent: { action, isDown in
                isDown ? SystemActionSender.makeEvent(action, isDown: true) : nil
            }, postEvent: { _ in posted = true })
        XCTAssertThrowsError(try sender.send(.volumeDown))
        XCTAssertFalse(posted)
    }

    @MainActor
    func testPermissionRevocationDuringPreparationPreventsBothTransitions() {
        var checks = 0
        var posted = false
        let sender = SystemActionSender(
            permissionGranted: {
                checks += 1; return checks == 1
            }, postEvent: { _ in posted = true })
        XCTAssertThrowsError(try sender.send(.volumeDown))
        XCTAssertEqual(checks, 2)
        XCTAssertFalse(posted)
    }

    @MainActor
    func testExecutorDefersSystemControlAndReportsSuccessOutsideTheTap() async {
        var postedCount = 0
        let sender = SystemActionSender(permissionGranted: { true }, postEvent: { _ in postedCount += 1 })
        let executor = ActionExecutor(inputSourceService: InputSourceService(), systemActionSender: sender)
        var returned = false
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            executor.execute(ShortcutAction(kind: "systemAction", systemAction: "volumeDown")) { result in
                XCTAssertTrue(returned)
                continuation.resume(returning: result)
            }
            XCTAssertEqual(postedCount, 0)
            returned = true
        }
        if case .failure(let error) = result { XCTFail(error.localizedDescription) }
        XCTAssertEqual(postedCount, 2)
    }

    @MainActor
    func testResetCancelsQueuedSystemControlBeforeAnyPosting() async {
        var postedCount = 0
        let sender = SystemActionSender(permissionGranted: { true }, postEvent: { _ in postedCount += 1 })
        let executor = ActionExecutor(inputSourceService: InputSourceService(), systemActionSender: sender)
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            executor.execute(ShortcutAction(kind: "systemAction", systemAction: "volumeDown")) {
                continuation.resume(returning: $0)
            }
            executor.observe(KeyboardEvent(kind: .reset))
        }
        guard case .failure(let error) = result else { return XCTFail("Expected cancellation") }
        XCTAssertTrue(error.localizedDescription.contains("canceled"))
        XCTAssertEqual(postedCount, 0)
    }

    @MainActor
    func testUnknownSystemControlFailsWithoutRequestingPermissionOrPosting() async {
        var permissionChecked = false
        var posted = false
        let sender = SystemActionSender(
            permissionGranted: {
                permissionChecked = true; return true
            }, postEvent: { _ in posted = true })
        let executor = ActionExecutor(inputSourceService: InputSourceService(), systemActionSender: sender)
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            executor.execute(ShortcutAction(kind: "systemAction", systemAction: "futureSystemControl")) {
                continuation.resume(returning: $0)
            }
        }
        guard case .failure = result else { return XCTFail("An unavailable system control must fail") }
        XCTAssertFalse(permissionChecked)
        XCTAssertFalse(posted)
    }
}
