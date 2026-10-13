.PHONY: build app icon test run format lint xcode

build:
	./scripts/swift-env.sh /usr/bin/xcrun swift build

app:
	./scripts/build-app.sh

icon:
	./scripts/swift-env.sh /usr/bin/xcrun swift scripts/create-icon.swift

test:
	./scripts/swift-env.sh /usr/bin/xcrun swift test

run: app
	open "build/Keyboard Shortcutter.app"

format:
	./scripts/swift-env.sh /usr/bin/xcrun swift format format --in-place --recursive Sources Tests Package.swift scripts/create-icon.swift

lint:
	./scripts/swift-env.sh /usr/bin/xcrun swift format lint --strict --recursive Sources Tests Package.swift scripts/create-icon.swift

xcode:
	./scripts/swift-env.sh /usr/bin/xcrun xcodebuild -project KeyboardShortcutter.xcodeproj -scheme KeyboardShortcutter -configuration Release -derivedDataPath build/xcode build
