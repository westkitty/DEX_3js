APP=build/DEX 3js.app
BIN=$(APP)/Contents/MacOS/DEX3js
SOURCES=Sources/DEX3js/main.swift Sources/DEX3js/ToolRuntime.swift Sources/DEX3js/AppearancePolicy.swift Sources/DEX3js/SceneOutputFramer.swift

.PHONY: build install run clean test integration-test uninstall
build:
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources/no-browser-fallback"
	swiftc -swift-version 5 -parse-as-library -framework SwiftUI -framework AppKit $(SOURCES) -o "$(BIN)"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp Resources/scene-bridge.mjs "$(APP)/Contents/Resources/scene-bridge.mjs"
	cp Resources/no-browser-fallback/open "$(APP)/Contents/Resources/no-browser-fallback/open"
	chmod 755 "$(APP)/Contents/Resources/no-browser-fallback/open"

install: build
	mkdir -p "$(HOME)/Applications" "$(HOME)/.local/bin"
	ditto "$(APP)" "$(HOME)/Applications/DEX 3js.app"
	install -m 755 bin/dex3js "$(HOME)/.local/bin/dex3js"
	install -m 755 bin/stop_owned.py "$(HOME)/.local/bin/dex3js-stop-owned.py"

run: build
	open -n "$(APP)"

test:
	node --check Resources/scene-bridge.mjs
	node Tests/scene-bridge-lifecycle-smoke.mjs
	swiftc -swift-version 5 Sources/DEX3js/SceneOutputFramer.swift Tests/SceneOutputFramerSmoke.swift -o /tmp/dex3js-scene-output-framer-smoke
	/tmp/dex3js-scene-output-framer-smoke
	rm -f /tmp/dex3js-scene-output-framer-smoke
	swiftc -swift-version 5 -parse-as-library -framework SwiftUI -framework AppKit -typecheck $(SOURCES)
	swiftc -swift-version 5 -DDEX3JS_TESTING -parse-as-library -framework SwiftUI -framework AppKit $(SOURCES) Tests/StoreLifecycleSmoke.swift -o /tmp/dex3js-store-lifecycle-smoke
	python3 Tests/run_store_lifecycle_smoke.py /tmp/dex3js-store-lifecycle-smoke
	rm -f /tmp/dex3js-store-lifecycle-smoke
	swiftc -swift-version 5 Sources/DEX3js/ToolRuntime.swift Tests/ControlCenterSmoke.swift -o /tmp/dex3js-control-center-smoke
	/tmp/dex3js-control-center-smoke
	rm -f /tmp/dex3js-control-center-smoke
	swiftc -swift-version 5 -framework SwiftUI -framework AppKit Sources/DEX3js/AppearancePolicy.swift Tests/AppearanceSmoke.swift -o /tmp/dex3js-appearance-smoke
	/tmp/dex3js-appearance-smoke
	rm -f /tmp/dex3js-appearance-smoke
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
