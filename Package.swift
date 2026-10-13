// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyboardShortcutter",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShortcutCore", targets: ["ShortcutCore"]),
        .executable(name: "KeyboardShortcutter", targets: ["KeyboardShortcutter"]),
    ],
    targets: [
        .target(name: "ShortcutCore"),
        .executableTarget(name: "KeyboardShortcutter", dependencies: ["ShortcutCore"]),
        .testTarget(name: "ShortcutCoreTests", dependencies: ["ShortcutCore"]),
        .testTarget(name: "MacIntegrationTests", dependencies: ["KeyboardShortcutter", "ShortcutCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
