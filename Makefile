APP=build/DEX 3js.app
BIN=$(APP)/Contents/MacOS/DEX3js

.PHONY: build install run clean test integration-test uninstall
build:
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	swiftc -swift-version 5 -parse-as-library -framework SwiftUI -framework AppKit Sources/DEX3js/main.swift -o "$(BIN)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"

install: build
	mkdir -p "$(HOME)/Applications" "$(HOME)/.local/bin"
	ditto "$(APP)" "$(HOME)/Applications/DEX 3js.app"
	install -m 755 bin/dex3js "$(HOME)/.local/bin/dex3js"
	install -m 755 bin/stop_owned.py "$(HOME)/.local/bin/dex3js-stop-owned.py"

run: build
	open -n "$(APP)"

test:
	swiftc -swift-version 5 -parse-as-library -framework SwiftUI -framework AppKit -typecheck Sources/DEX3js/main.swift
	swiftc -swift-version 5 Tests/ProcessGroupSmoke.swift -o /tmp/dex3js-process-group-smoke
	/tmp/dex3js-process-group-smoke
	rm -f /tmp/dex3js-process-group-smoke

integration-test:
	/usr/bin/python3 Tests/owned-stop-integration.py

clean:
	rm -rf build

uninstall:
	rm -rf "$(HOME)/Applications/DEX 3js.app"
	rm -f "$(HOME)/.local/bin/dex3js"
	rm -f "$(HOME)/.local/bin/dex3js-stop-owned.py"
