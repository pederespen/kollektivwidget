APP_NAME = KollektivWidget
BUNDLE_ID = com.pespen.kollektivwidget
BUILD_DIR = build
APP_DIR = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources
ICONSET_DIR = $(BUILD_DIR)/AppIcon.iconset

# Swift compiler flags
SWIFT_FLAGS = -O -Xlinker -rpath -Xlinker @executable_path/../Frameworks

.PHONY: all clean run build install dmg release

all: build

build: $(APP_DIR)/Contents/MacOS/$(APP_NAME)

$(APP_DIR)/Contents/MacOS/$(APP_NAME): KollektivWidget/*.swift
	@echo "Building $(APP_NAME)..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	
	# Copy Info.plist
	@cp KollektivWidget/Info.plist $(CONTENTS_DIR)/
	
	# Try to compile asset catalog (preferred when full Xcode is available)
	@if [ -d "KollektivWidget/Assets.xcassets" ]; then \
		echo "🎨 Compiling asset catalog (if available)..."; \
		if xcrun actool --version >/dev/null 2>&1; then \
			xcrun actool --compile "$(RESOURCES_DIR)" \
				--platform macosx \
				--minimum-deployment-target 13.0 \
				--app-icon AppIcon \
				"KollektivWidget/Assets.xcassets" >/dev/null || true; \
    		fi; \
		if [ ! -f "$(RESOURCES_DIR)/AppIcon.icns" ]; then \
			echo "🧩 actool output not found; generating AppIcon.icns via iconutil..."; \
			rm -rf "$(ICONSET_DIR)"; \
			mkdir -p "$(ICONSET_DIR)"; \
			set -e; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/16.png "$(ICONSET_DIR)/icon_16x16.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/32.png "$(ICONSET_DIR)/icon_16x16@2x.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/32.png "$(ICONSET_DIR)/icon_32x32.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/64.png "$(ICONSET_DIR)/icon_32x32@2x.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/128.png "$(ICONSET_DIR)/icon_128x128.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/256.png "$(ICONSET_DIR)/icon_128x128@2x.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/256.png "$(ICONSET_DIR)/icon_256x256.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/512.png "$(ICONSET_DIR)/icon_256x256@2x.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/512.png "$(ICONSET_DIR)/icon_512x512.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/1024.png "$(ICONSET_DIR)/icon_512x512@2x.png"; \
			iconutil -c icns "$(ICONSET_DIR)" -o "$(RESOURCES_DIR)/AppIcon.icns"; \
			echo "✅ Generated $(RESOURCES_DIR)/AppIcon.icns"; \
		fi; \
	fi
	
	# Compile Swift files
	@swiftc $(SWIFT_FLAGS) \
		-o $(MACOS_DIR)/$(APP_NAME) \
		KollektivWidget/*.swift

	# Ad-hoc code sign the app bundle to ensure Notification registration on macOS 15
	@echo "\xF0\x9F\x94\x8F Code signing (ad-hoc)..."
	@/usr/bin/codesign --force --deep --timestamp=none --sign - $(APP_DIR)
	
	@echo "✅ Built $(APP_NAME).app successfully!"

run: install
	@echo "🚀 Running installed $(APP_NAME) from /Applications..."
	@open /Applications/$(APP_NAME).app

install: build
	@echo "📦 Installing $(APP_NAME) to /Applications..."
	@cp -r $(APP_DIR) /Applications/
	@xattr -dr com.apple.quarantine /Applications/$(APP_NAME).app || true
	@echo "✅ Installed! You can now run $(APP_NAME) from Applications folder"

clean:
	@echo "🧹 Cleaning build directory..."
	@rm -rf $(BUILD_DIR)

reinstall: clean install

verify-sign:
	@/usr/bin/codesign --display --verbose=2 /Applications/$(APP_NAME).app | cat

dmg: build
	@echo "💿 Creating DMG package..."
	@./create-dmg.sh
	@echo "✅ DMG package ready for distribution!"

release: dmg
	@echo "🎉 Release package created!"
	@echo "📦 Upload build/$(APP_NAME).dmg to GitHub releases"

debug:
	@echo "🐛 Building debug version..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	@cp KollektivWidget/Info.plist $(CONTENTS_DIR)/
	@if [ -d "KollektivWidget/Assets.xcassets" ]; then \
		echo "🎨 Compiling asset catalog (debug, if available)..."; \
		if xcrun actool --version >/dev/null 2>&1; then \
			xcrun actool --compile "$(RESOURCES_DIR)" \
				--platform macosx \
				--minimum-deployment-target 13.0 \
				--app-icon AppIcon \
				"KollektivWidget/Assets.xcassets" >/dev/null || true; \
    		fi; \
		if [ ! -f "$(RESOURCES_DIR)/AppIcon.icns" ]; then \
			echo "🧩 actool output not found; generating AppIcon.icns via iconutil (debug)..."; \
			rm -rf "$(ICONSET_DIR)"; \
			mkdir -p "$(ICONSET_DIR)"; \
			set -e; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/16.png "$(ICONSET_DIR)/icon_16x16.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/32.png "$(ICONSET_DIR)/icon_16x16@2x.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/32.png "$(ICONSET_DIR)/icon_32x32.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/64.png "$(ICONSET_DIR)/icon_32x32@2x.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/128.png "$(ICONSET_DIR)/icon_128x128.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/256.png "$(ICONSET_DIR)/icon_128x128@2x.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/256.png "$(ICONSET_DIR)/icon_256x256.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/512.png "$(ICONSET_DIR)/icon_256x256@2x.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/512.png "$(ICONSET_DIR)/icon_512x512.png"; \
			cp KollektivWidget/Assets.xcassets/AppIcon.appiconset/1024.png "$(ICONSET_DIR)/icon_512x512@2x.png"; \
			iconutil -c icns "$(ICONSET_DIR)" -o "$(RESOURCES_DIR)/AppIcon.icns"; \
			echo "✅ Generated $(RESOURCES_DIR)/AppIcon.icns (debug)"; \
		fi; \
	fi
	@swiftc -g -o $(MACOS_DIR)/$(APP_NAME) KollektivWidget/*.swift
	@echo "✅ Debug build complete!"
