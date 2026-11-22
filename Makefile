PROJECT := Moonlet.xcodeproj
SCHEME := Moonlet
DERIVED := build/DerivedData
DESTINATION := platform=macOS,arch=arm64
APP := $(DERIVED)/Build/Products/Debug/Moonlet.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED) -quiet
RELEASE_APP := $(DERIVED)/Build/Products/Release/Moonlet.app
RELEASE_DIR := build/release

.PHONY: generate build test snapshots run stop install release icon sounds examples videos clean

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
	@open $(APP) 2> /dev/null || (sleep 1 && open $(APP))

stop:
	@-pkill -x Moonlet; while pgrep -x Moonlet > /dev/null; do sleep 0.1; done

install: generate
	$(XCODEBUILD) -configuration Release build
	@$(MAKE) --no-print-directory stop
	rm -rf /Applications/Moonlet.app
	ditto $(RELEASE_APP) /Applications/Moonlet.app
	@echo "Installed /Applications/Moonlet.app"

release: generate sounds
	$(XCODEBUILD) -configuration Release build
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	ditto -c -k --sequesterRsrc --keepParent $(RELEASE_APP) $(RELEASE_DIR)/Moonlet.zip
	MOONLET_LIBRARY=$(RELEASE_DIR)/Moonlet tools/install-examples.sh examples build/sounds > /dev/null
	ditto -c -k --keepParent $(RELEASE_DIR)/Moonlet $(RELEASE_DIR)/Moonlet-Examples.zip
	rm -rf $(RELEASE_DIR)/Moonlet
	@ls -lh $(RELEASE_DIR)

icon:
	mkdir -p build/tools
	swiftc -swift-version 5 -O tools/RenderIcon/main.swift Moonlet/App/MenuBarIcon.swift -o build/tools/RenderIcon
	build/tools/RenderIcon appiconset Moonlet/Assets.xcassets/AppIcon.appiconset

sounds:
	tools/make-sounds.sh build/sounds

examples: sounds
	tools/install-examples.sh examples build/sounds

videos: sounds
	tools/download-videos.sh examples/videos.tsv build/sounds

clean:
	rm -rf build $(PROJECT)
