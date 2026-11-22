PROJECT := Moonlet.xcodeproj
SCHEME := Moonlet
DERIVED := build/DerivedData
DESTINATION := platform=macOS,arch=arm64
APP := $(DERIVED)/Build/Products/Debug/Moonlet.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED) -quiet

.PHONY: generate build test snapshots run stop clean

generate:
	xcodegen generate --quiet

build: generate
	$(XCODEBUILD) build

test: generate
	$(XCODEBUILD) test

snapshots: generate
	mkdir -p build/snapshots
	TEST_RUNNER_MOONLET_SNAPSHOT_DIR=$(CURDIR)/build/snapshots $(XCODEBUILD) test -only-testing:MoonletTests/WallpaperReviewSnapshots

run: build stop
	open $(APP)

stop:
	@-pkill -x Moonlet; while pgrep -x Moonlet > /dev/null; do sleep 0.1; done

clean:
	rm -rf build $(PROJECT)
