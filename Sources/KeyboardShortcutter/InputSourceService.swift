import Carbon
import Foundation

@MainActor
protocol InputSourceSelecting {
    func enumerate() -> [InputSourceService.Source]
    func select(id: String) throws
}

@MainActor
final class InputSourceService: InputSourceSelecting {
    struct Source: Identifiable, Hashable {
        let id: String
        let name: String
        let languages: [String]
        var inputModeID: String? = nil

    }

    enum Failure: LocalizedError {
        case missingSource(String)
        case selectionFailed(String, OSStatus)

        var errorDescription: String? {
            switch self {
            case .missingSource(let id):
                return
                    "The configured input source (\(id)) is unavailable. Enable it in System Settings → Keyboard → Text Input, then select it again in Settings."
            case .selectionFailed(let name, let status):
                return
                    "macOS could not select \(name) (error \(status)). Check that its input method is enabled."
            }
        }
    }

    func enumerate() -> [Source] {
        enabledSources().compactMap { source in
            guard let id: String = property(source, kTISPropertyInputSourceID),
                let name: String = property(source, kTISPropertyLocalizedName)
            else { return nil }
            let languages: [String] = property(source, kTISPropertyInputSourceLanguages) ?? []
            let inputModeID: String? = property(source, kTISPropertyInputModeID)
            return Source(id: id, name: name, languages: languages, inputModeID: inputModeID)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func select(id: String) throws {
        guard
            let source = enabledSources().first(where: {
                let candidate: String? = property($0, kTISPropertyInputSourceID)
                return candidate == id
            })
        else { throw Failure.missingSource(id) }
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            let name: String = property(source, kTISPropertyLocalizedName) ?? id
            throw Failure.selectionFailed(name, status)
        }
    }

    private func enabledSources() -> [TISInputSource] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String,
            kTISPropertyInputSourceIsEnabled as String: true,
            kTISPropertyInputSourceIsSelectCapable as String: true,
        ]
        // The Create rule transfers ownership; Array retains each source after the CF array dies.
        guard let sources = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue()
        else { return [] }
        return sources as? [TISInputSource] ?? []
    }

    private func property<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue() as? T
    }
}
