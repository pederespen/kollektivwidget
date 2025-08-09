APP_NAME = RuterWidget
BUNDLE_ID = com.yourname.ruterwidget
BUILD_DIR = build
APP_DIR = $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR = $(APP_DIR)/Contents
MACOS_DIR = $(CONTENTS_DIR)/MacOS
RESOURCES_DIR = $(CONTENTS_DIR)/Resources

# Swift compiler flags
SWIFT_FLAGS = -O -Xlinker -rpath -Xlinker @executable_path/../Frameworks

.PHONY: all clean run build install

all: build

build: $(APP_DIR)/Contents/MacOS/$(APP_NAME)

$(APP_DIR)/Contents/MacOS/$(APP_NAME): RuterWidget/RuterWidget/*.swift
	@echo "Building $(APP_NAME)..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	
	# Copy Info.plist
	@cp RuterWidget/RuterWidget/Info.plist $(CONTENTS_DIR)/
	
	# Compile Swift files
	@swiftc $(SWIFT_FLAGS) \
		-o $(MACOS_DIR)/$(APP_NAME) \
		RuterWidget/RuterWidget/*.swift

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

debug:
	@echo "🐛 Building debug version..."
	@mkdir -p $(MACOS_DIR)
	@mkdir -p $(RESOURCES_DIR)
	@cp RuterWidget/RuterWidget/Info.plist $(CONTENTS_DIR)/
	@swiftc -g -o $(MACOS_DIR)/$(APP_NAME) RuterWidget/RuterWidget/*.swift
	@echo "✅ Debug build complete!"
