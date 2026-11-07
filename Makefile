APP=build/DEX 3js.app
BIN=$(APP)/Contents/MacOS/DEX3js
SOURCES=Sources/DEX3js/main.swift Sources/DEX3js/ToolRuntime.swift

.PHONY: build install run clean test integration-test uninstall
build:
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	swiftc -swift-version 5 -parse-as-library -framework SwiftUI -framework AppKit $(SOURCES) -o "$(BIN)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/scene-bridge.mjs "$(APP)/Contents/Resources/scene-bridge.mjs"

install: build
	mkdir -p "$(HOME)/Applications" "$(HOME)/.local/bin"
	ditto "$(APP)" "$(HOME)/Applications/DEX 3js.app"
	install -m 755 bin/dex3js "$(HOME)/.local/bin/dex3js"
	install -m 755 bin/stop_owned.py "$(HOME)/.local/bin/dex3js-stop-owned.py"

run: build
	open -n "$(APP)"

test:
	node --check Resources/scene-bridge.mjs
	swiftc -swift-version 5 -parse-as-library -framework SwiftUI -framework AppKit -typecheck $(SOURCES)
	swiftc -swift-version 5 Sources/DEX3js/ToolRuntime.swift Tests/ControlCenterSmoke.swift -o /tmp/dex3js-control-center-smoke
	/tmp/dex3js-control-center-smoke
	rm -f /tmp/dex3js-control-center-smoke
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
