CC       := clang
ARCH     := arm64
MIN_VER  := 15.0
VERSION  ?= 2.0.0
CFLAGS   := -arch $(ARCH) -mmacosx-version-min=$(MIN_VER) -std=c17 -O2 -Wall -Wextra -Wno-unused-parameter -fPIC
LDFLAGS  := -arch $(ARCH) -mmacosx-version-min=$(MIN_VER)
OUT_DIR  := out

DOBBY_DIR  := build/dobby
DOBBY_LIBS := $(DOBBY_DIR)/libdobby.a \
              $(DOBBY_DIR)/builtin-plugin/SymbolResolver/libdobby_symbol_resolver.a \
              $(DOBBY_DIR)/builtin-plugin/SymbolResolver/libmacho_ctx_kit.a \
              $(DOBBY_DIR)/builtin-plugin/SymbolResolver/libshared_cache_ctx_kit.a \
              $(DOBBY_DIR)/external/osbase/libosbase.a \
              $(DOBBY_DIR)/external/logging/liblogging.a

STEAM_BRIDGE_ARM64 := $(OUT_DIR)/positron-steam.arm64.dylib
STEAM_BRIDGE_X86   := $(OUT_DIR)/positron-steam.x86_64.dylib
STEAM_BRIDGE_DYLIB := $(OUT_DIR)/positron-steam.dylib
SUPERVISOR_BIN     := $(OUT_DIR)/positron-run
APP_BUNDLE         := $(OUT_DIR)/Positron.app

TEST_STEAM_BRIDGE  := $(OUT_DIR)/test_steam_bridge
TEST_PE_PATCHER    := $(OUT_DIR)/test_pe_patcher
TEST_SUPERVISOR    := $(OUT_DIR)/test_supervisor

.PHONY: all clean dylib supervisor swift-build app package c-tests swift-test test dobby

all: dylib supervisor swift-build app

$(OUT_DIR):
	@mkdir -p $(OUT_DIR) $(OUT_DIR)/generated

dobby: $(DOBBY_DIR)/libdobby.a

$(DOBBY_DIR)/libdobby.a:
	@echo "==> Building Dobby static library (arm64)..."
	@cmake -S vendor/dobby -B $(DOBBY_DIR) \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=$(MIN_VER) \
		-DDOBBY_BUILD_EXAMPLE=OFF \
		-DDOBBY_BUILD_TEST=OFF \
		-DDOBBY_BUILD_KERNEL_MODE=OFF \
		-DDOBBY_DEBUG=OFF \
		-DDOBBY_GENERATE_SHARED=OFF
	@cmake --build $(DOBBY_DIR) -j4

$(OUT_DIR)/generated/compat_run.h: steam-bridge/engine/feats/compat_run.sh steam-bridge/engine/embed_script.py | $(OUT_DIR)
	@python3 steam-bridge/engine/embed_script.py steam-bridge/engine/feats/compat_run.sh $(OUT_DIR)/generated/compat_run.h RUN_SCRIPT

dylib: $(STEAM_BRIDGE_DYLIB)

$(STEAM_BRIDGE_ARM64): $(DOBBY_DIR)/libdobby.a $(OUT_DIR)/generated/compat_run.h \
	steam-bridge/engine/core/loader.c \
	steam-bridge/engine/core/macho.c \
	steam-bridge/engine/resolver/anchor.c \
	steam-bridge/engine/resolver/aob.c \
	steam-bridge/engine/resolver/resolver.c \
	steam-bridge/engine/resolver/sigdb.c \
	steam-bridge/engine/util/log.c \
	steam-bridge/engine/util/file.c \
	steam-bridge/engine/util/peicon.c \
	steam-bridge/engine/hooks/hooks.c \
	steam-bridge/engine/hooks/hook_compat.c \
	steam-bridge/engine/hooks/hook_shortcut.c \
	steam-bridge/engine/hooks/hook_icon.c \
	steam-bridge/engine/hooks/hook_shortcut_bundle.c \
	steam-bridge/engine/hooks/hook_webui.c \
	steam-bridge/engine/hooks/hook_webpatch.c \
	steam-bridge/engine/hooks/hook_spawn.c \
	steam-bridge/engine/hooks/hook_launch.c \
	steam-bridge/engine/hooks/hook_activate.c \
	steam-bridge/engine/feats/compat.c \
	steam-bridge/engine/feats/webui.c \
	steam-bridge/engine/feats/compatsvc.c \
	steam-bridge/engine/feats/usershortcuts.c \
	steam-bridge/engine/feats/webpatch.c \
	steam-bridge/engine/feats/nativeplatform.c \
	steam-bridge/engine/feats/input_access.c \
	steam-bridge/vendor/cJSON.c \
	steam-bridge/src/mp_macho.c \
	steam-bridge/src/mp_resolver.c \
	steam-bridge/src/mp_web_inject.c
	$(CC) $(CFLAGS) $(LDFLAGS) -dynamiclib \
		-install_name @rpath/positron-steam.dylib \
		-Isteam-bridge/include -Isteam-bridge/engine -Isteam-bridge/vendor -Ivendor/dobby/include -I$(OUT_DIR)/generated \
		-framework CoreFoundation -framework CoreGraphics -lc++ \
		-o $@ \
		steam-bridge/engine/core/loader.c \
	steam-bridge/engine/core/macho.c \
	steam-bridge/engine/resolver/anchor.c \
	steam-bridge/engine/resolver/aob.c \
	steam-bridge/engine/resolver/resolver.c \
	steam-bridge/engine/resolver/sigdb.c \
	steam-bridge/engine/util/log.c \
	steam-bridge/engine/util/file.c \
	steam-bridge/engine/util/peicon.c \
	steam-bridge/engine/hooks/hooks.c \
	steam-bridge/engine/hooks/hook_compat.c \
	steam-bridge/engine/hooks/hook_shortcut.c \
	steam-bridge/engine/hooks/hook_icon.c \
	steam-bridge/engine/hooks/hook_shortcut_bundle.c \
	steam-bridge/engine/hooks/hook_webui.c \
	steam-bridge/engine/hooks/hook_webpatch.c \
	steam-bridge/engine/hooks/hook_spawn.c \
	steam-bridge/engine/hooks/hook_launch.c \
	steam-bridge/engine/hooks/hook_activate.c \
	steam-bridge/engine/feats/compat.c \
	steam-bridge/engine/feats/webui.c \
	steam-bridge/engine/feats/compatsvc.c \
	steam-bridge/engine/feats/usershortcuts.c \
	steam-bridge/engine/feats/webpatch.c \
	steam-bridge/engine/feats/nativeplatform.c \
	steam-bridge/engine/feats/input_access.c \
	steam-bridge/vendor/cJSON.c \
	steam-bridge/src/mp_macho.c \
	steam-bridge/src/mp_resolver.c \
	steam-bridge/src/mp_web_inject.c \
		$(DOBBY_LIBS)

$(STEAM_BRIDGE_X86): steam-bridge/engine/stub_x86_64.c | $(OUT_DIR)
	$(CC) -arch x86_64 -mmacosx-version-min=$(MIN_VER) -dynamiclib \
		-install_name @rpath/positron-steam.dylib \
		-o $@ steam-bridge/engine/stub_x86_64.c

$(STEAM_BRIDGE_DYLIB): $(STEAM_BRIDGE_ARM64) $(STEAM_BRIDGE_X86)
	lipo -create $^ -output $@
	codesign -fs - $@

supervisor: $(SUPERVISOR_BIN)

$(SUPERVISOR_BIN): $(OUT_DIR) \
	runner-supervisor/src/mp_reg_editor.c \
	runner-supervisor/src/mp_prefix_migrator.c \
	runner-supervisor/src/mp_supervisor.c \
	runner-supervisor/src/main.c \
	ntdll-patcher/src/mp_pe_patcher.c
	$(CC) $(CFLAGS) $(LDFLAGS) \
		-Irunner-supervisor/include \
		-Intdll-patcher/include \
		-o $@ \
		runner-supervisor/src/mp_reg_editor.c \
		runner-supervisor/src/mp_prefix_migrator.c \
		runner-supervisor/src/mp_supervisor.c \
		runner-supervisor/src/main.c \
		ntdll-patcher/src/mp_pe_patcher.c

swift-build:
	swift build -c release

app: $(STEAM_BRIDGE_DYLIB) $(SUPERVISOR_BIN) swift-build
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources/signatures/macos.arm64"
	@BIN_PATH=$$(swift build -c release --show-bin-path); \
		cp "$$BIN_PATH/PositronApp" "$(APP_BUNDLE)/Contents/MacOS/PositronApp"; \
		cp "$$BIN_PATH/positron" "$(APP_BUNDLE)/Contents/Resources/positron"
	@cp "$(STEAM_BRIDGE_DYLIB)" "$(APP_BUNDLE)/Contents/Resources/positron-steam.dylib"
	@cp "$(SUPERVISOR_BIN)" "$(APP_BUNDLE)/Contents/Resources/positron-run"
	@cp "Resources/AppIcon.icns" "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	@cp "LICENSE" "$(APP_BUNDLE)/Contents/Resources/LICENSE"
	@cp "THIRD_PARTY_NOTICES.md" "$(APP_BUNDLE)/Contents/Resources/THIRD_PARTY_NOTICES.md"
	@cp "steam-bridge/engine/feats/compat_run.sh" "$(APP_BUNDLE)/Contents/Resources/run"
	@cp Resources/signatures/macos.arm64/*.json "$(APP_BUNDLE)/Contents/Resources/signatures/macos.arm64/"
	@chmod +x "$(APP_BUNDLE)/Contents/MacOS/PositronApp" \
		"$(APP_BUNDLE)/Contents/Resources/positron-run" \
		"$(APP_BUNDLE)/Contents/Resources/positron"
	@printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0">' \
		'<dict>' \
		'  <key>CFBundleName</key><string>Positron</string>' \
		'  <key>CFBundleDisplayName</key><string>Positron</string>' \
		'  <key>CFBundleIdentifier</key><string>com.positron.app</string>' \
		'  <key>CFBundleVersion</key><string>$(VERSION)</string>' \
		'  <key>CFBundleShortVersionString</key><string>$(VERSION)</string>' \
		'  <key>CFBundleExecutable</key><string>PositronApp</string>' \
		'  <key>CFBundleIconFile</key><string>AppIcon</string>' \
		'  <key>CFBundlePackageType</key><string>APPL</string>' \
		'  <key>LSMinimumSystemVersion</key><string>15.0</string>' \
		'  <key>NSHighResolutionCapable</key><true/>' \
		'  <key>NSRemovableVolumesUsageDescription</key><string>Positron accesses Steam Libraries and Windows game files stored on external drives.</string>' \
		'  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Andrey Kozlov and Positron Contributors. Released under the MIT License.</string>' \
		'  <key>NSPrincipalClass</key><string>NSApplication</string>' \
		'</dict>' \
		'</plist>' > "$(APP_BUNDLE)/Contents/Info.plist"
	@/usr/bin/codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "==> Built and signed $(APP_BUNDLE) (v$(VERSION))"

package: app
	@echo "==> Packaging release artifacts in $(OUT_DIR)..."
	@rm -f "$(OUT_DIR)/Positron-macOS-arm64.zip" "$(OUT_DIR)/Positron-macOS-arm64.dmg" "$(OUT_DIR)/SHA256SUMS.txt"
	@ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(OUT_DIR)/Positron-macOS-arm64.zip"
	@DMG_STAGE="$$(mktemp -d)"; \
		cp -R "$(APP_BUNDLE)" "$$DMG_STAGE/Positron.app"; \
		cp "LICENSE" "$$DMG_STAGE/LICENSE.txt"; \
		ln -s /Applications "$$DMG_STAGE/Applications"; \
		hdiutil create -volname "Positron" -srcfolder "$$DMG_STAGE" -ov -format UDZO "$(OUT_DIR)/Positron-macOS-arm64.dmg" >/dev/null; \
		rm -rf "$$DMG_STAGE"
	@cd "$(OUT_DIR)" && shasum -a 256 Positron-macOS-arm64.zip Positron-macOS-arm64.dmg > SHA256SUMS.txt
	@echo "==> Created $(OUT_DIR)/Positron-macOS-arm64.dmg, $(OUT_DIR)/Positron-macOS-arm64.zip, and $(OUT_DIR)/SHA256SUMS.txt"

$(TEST_STEAM_BRIDGE): $(OUT_DIR) \
	steam-bridge/tests/test_steam_bridge.c \
	steam-bridge/src/mp_macho.c \
	steam-bridge/src/mp_resolver.c \
	steam-bridge/src/mp_web_inject.c
	$(CC) $(CFLAGS) $(LDFLAGS) \
		-Isteam-bridge/include \
		-o $@ \
		steam-bridge/tests/test_steam_bridge.c \
		steam-bridge/src/mp_macho.c \
		steam-bridge/src/mp_resolver.c \
		steam-bridge/src/mp_web_inject.c

$(TEST_PE_PATCHER): $(OUT_DIR) \
	ntdll-patcher/tests/test_pe_patcher.c \
	ntdll-patcher/src/mp_pe_patcher.c
	$(CC) $(CFLAGS) $(LDFLAGS) \
		-Intdll-patcher/include \
		-o $@ \
		ntdll-patcher/tests/test_pe_patcher.c \
		ntdll-patcher/src/mp_pe_patcher.c

$(TEST_SUPERVISOR): $(OUT_DIR) \
	runner-supervisor/tests/test_supervisor.c \
	runner-supervisor/src/mp_reg_editor.c \
	runner-supervisor/src/mp_prefix_migrator.c \
	runner-supervisor/src/mp_supervisor.c \
	ntdll-patcher/src/mp_pe_patcher.c
	$(CC) $(CFLAGS) $(LDFLAGS) \
		-Irunner-supervisor/include \
		-Intdll-patcher/include \
		-o $@ \
		runner-supervisor/tests/test_supervisor.c \
		runner-supervisor/src/mp_reg_editor.c \
		runner-supervisor/src/mp_prefix_migrator.c \
		runner-supervisor/src/mp_supervisor.c \
		ntdll-patcher/src/mp_pe_patcher.c

c-tests: $(TEST_STEAM_BRIDGE) $(TEST_PE_PATCHER) $(TEST_SUPERVISOR)
	@echo "==> Running Positron steam-bridge tests..."
	./$(TEST_STEAM_BRIDGE)
	@echo "==> Running Positron ntdll-patcher tests..."
	./$(TEST_PE_PATCHER)
	@echo "==> Running Positron runner-supervisor tests..."
	./$(TEST_SUPERVISOR)

swift-test:
	swift test

test: dylib supervisor c-tests swift-test

clean:
	rm -rf $(OUT_DIR) .build
