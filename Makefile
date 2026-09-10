APP      := Lanes
CONFIG   ?= release
VERSION  ?= 0.0.0
BUILD_NUMBER ?= 0
# "-" is an ad-hoc signature; pass a "Developer ID Application: …" identity for a distributable build
SIGN_IDENTITY ?= -
ifeq ($(SIGN_IDENTITY),-)
SIGN_FLAGS :=
else
SIGN_FLAGS := --options runtime --timestamp
endif
BUILD    := .build/$(CONFIG)
BUNDLE   := Build/$(APP).app
CONTENTS := $(BUNDLE)/Contents
SPARKLE  := .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
FRAMEWORK := $(CONTENTS)/Frameworks/Sparkle.framework

.PHONY: build app run test clean icon

build:
	swift build -c $(CONFIG)

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BUILD)/$(APP) $(CONTENTS)/MacOS/
	cp -R $(BUILD)/*.bundle $(CONTENTS)/Resources/
	cp Resources/Info.plist $(CONTENTS)/
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" $(CONTENTS)/Info.plist
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" $(CONTENTS)/Info.plist
	cp -R Resources/Themes $(CONTENTS)/Resources/Themes
	cp Resources/AppIcon.icns $(CONTENTS)/Resources/
	mkdir -p $(CONTENTS)/Frameworks
	cp -R $(SPARKLE) $(CONTENTS)/Frameworks/
	install_name_tool -add_rpath @executable_path/../Frameworks $(CONTENTS)/MacOS/$(APP)
ifneq ($(SIGN_IDENTITY),-)
	# Sparkle's helpers must carry our identity for the hardened runtime and notarization
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) $(FRAMEWORK)/Versions/B/XPCServices/Installer.xpc
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) --preserve-metadata=entitlements $(FRAMEWORK)/Versions/B/XPCServices/Downloader.xpc
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) $(FRAMEWORK)/Versions/B/Autoupdate
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) $(FRAMEWORK)/Versions/B/Updater.app
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) $(FRAMEWORK)
endif
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) $(BUNDLE)
	@echo "built $(BUNDLE)"

# make run REPO=/path/to/repo
run: app
	open $(BUNDLE) --args --repo=$(REPO)

test:
	swift test

ICON_DIR := Resources/AppIcon
ICONSET  := $(ICON_DIR)/AppIcon.iconset

# renders Resources/AppIcon/icon.svg into the 1024 px master and the .icns the bundle ships
icon:
	mkdir -p .build
	swiftc -O Scripts/rendersvg.swift -o .build/rendersvg
	.build/rendersvg $(ICON_DIR)/icon.svg $(ICON_DIR)/icon-1024.png
	rm -rf $(ICONSET) && mkdir -p $(ICONSET)
	for s in 16 32 128 256 512; do \
	  sips -z $$s $$s $(ICON_DIR)/icon-1024.png --out $(ICONSET)/icon_$${s}x$${s}.png >/dev/null; \
	  sips -z $$((s*2)) $$((s*2)) $(ICON_DIR)/icon-1024.png --out $(ICONSET)/icon_$${s}x$${s}@2x.png >/dev/null; \
	done
	iconutil -c icns $(ICONSET) -o Resources/AppIcon.icns
	rm -rf $(ICONSET)

clean:
	rm -rf .build Build

sync-scanners:
	for g in javascript python yaml css; do \
	  cp .build/checkouts/tree-sitter-$$g/src/scanner.c Sources/GrammarScanners/$$g/; \
	  cp .build/checkouts/tree-sitter-$$g/src/tree_sitter/*.h Sources/GrammarScanners/$$g/tree_sitter/; \
	done
	cp .build/checkouts/tree-sitter-yaml/src/schema.*.c Sources/GrammarScanners/yaml/
