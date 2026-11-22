PROJECT := Moonlet.xcodeproj
SCHEME := Moonlet
DERIVED := build/DerivedData
DESTINATION := platform=macOS,arch=arm64
APP := $(DERIVED)/Build/Products/Debug/Moonlet.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED) -quiet

.PHONY: generate build test run stop clean

generate:
	xcodegen generate --quiet

build: generate
	$(XCODEBUILD) build

test: generate
	$(XCODEBUILD) test

run: build stop
	open $(APP)

stop:
	@-pkill -x Moonlet; while pgrep -x Moonlet > /dev/null; do sleep 0.1; done

clean:
	rm -rf build $(PROJECT)
