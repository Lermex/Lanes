APP      := Lanes
CONFIG   ?= release
BUILD    := .build/$(CONFIG)
BUNDLE   := Build/$(APP).app
CONTENTS := $(BUNDLE)/Contents

.PHONY: build app run test clean

build:
	swift build -c $(CONFIG)

app: build
	rm -rf $(BUNDLE)
	mkdir -p $(CONTENTS)/MacOS $(CONTENTS)/Resources
	cp $(BUILD)/$(APP) $(CONTENTS)/MacOS/
	cp -R $(BUILD)/*.bundle $(CONTENTS)/Resources/
	cp Resources/Info.plist $(CONTENTS)/
	cp -R Resources/Themes $(CONTENTS)/Resources/Themes
	codesign --force --sign - $(BUNDLE)
	@echo "built $(BUNDLE)"

# make run REPO=/path/to/repo
run: app
	open $(BUNDLE) --args --repo=$(REPO)

test:
	swift test

clean:
	rm -rf .build Build

sync-scanners:
	for g in javascript python yaml css; do \
	  cp .build/checkouts/tree-sitter-$$g/src/scanner.c Sources/GrammarScanners/$$g/; \
	  cp .build/checkouts/tree-sitter-$$g/src/tree_sitter/*.h Sources/GrammarScanners/$$g/tree_sitter/; \
	done
	cp .build/checkouts/tree-sitter-yaml/src/schema.*.c Sources/GrammarScanners/yaml/
