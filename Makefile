APP_NAME := AntigravityQuota
APP_BUNDLE := build/$(APP_NAME).app
BINARY_PATH := .build/release/$(APP_NAME)
SWIFTPM_FLAGS := --disable-sandbox --scratch-path .build --cache-path /tmp/agy-quota-swiftpm-cache
SWIFTCOMPILE_FLAGS :=-Xswiftc -Osize -Xswiftc -wmo -Xswiftc -enforce-exclusivity=unchecked -Xcc -Os -Xlinker -dead_strip -Xlinker -S
SWIFTPM_ENV := CLANG_MODULE_CACHE_PATH=/tmp/agy-quota-clang-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/agy-quota-module-cache

.PHONY: all icon build test run install clean

all: build

icon:
	$(SWIFTPM_ENV) swift scripts/generate_icon.swift

build:
	$(SWIFTPM_ENV) swift build -c release $(SWIFTCOMPILE_FLAGS) $(SWIFTPM_FLAGS)
	strip -r -u -x $(BINARY_PATH)
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BINARY_PATH) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	printf 'APPL????' > $(APP_BUNDLE)/Contents/PkgInfo
	codesign --force --deep --sign - $(APP_BUNDLE)

test:
	$(SWIFTPM_ENV) swift test $(SWIFTPM_FLAGS)

run: build
	open $(APP_BUNDLE)

install: build
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP_BUNDLE) /Applications/$(APP_NAME).app

clean:
	rm -rf .build build
