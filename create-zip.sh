#!/bin/bash

# ZIP Distribution Script for KollektivWidget
# Creates a simple ZIP file for distribution without DMG mounting issues

set -e

APP_NAME="KollektivWidget"
BUILD_DIR="build"
ZIP_DIR="$BUILD_DIR/zip"

# Get version from Info.plist
if [ -f "KollektivWidget/Info.plist" ]; then
    VERSION=$(defaults read "$(pwd)/KollektivWidget/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
else
    VERSION="1.0"
fi

ZIP_FILE="$BUILD_DIR/${APP_NAME}-v${VERSION}.zip"

echo "📦 Creating ZIP distribution for $APP_NAME v$VERSION..."

# Clean up any existing files
rm -f "$ZIP_FILE"
rm -rf "$ZIP_DIR"

# Build the app first
echo "🔨 Building application..."
make clean build

# Create distribution directory
mkdir -p "$ZIP_DIR"

# Copy app bundle
echo "📋 Preparing app bundle..."
cp -R "$BUILD_DIR/$APP_NAME.app" "$ZIP_DIR/"

# Remove quarantine attributes and extended attributes
echo "🧹 Cleaning extended attributes..."
xattr -cr "$ZIP_DIR/$APP_NAME.app" || true

# Create installation instructions
cat > "$ZIP_DIR/README.txt" << EOF
KollektivWidget v${VERSION}
==========================

INSTALLATION:
1. Copy KollektivWidget.app to your Applications folder
2. Right-click KollektivWidget.app and select "Open"
3. Click "Open" when prompted about unverified developer
4. Grant notification permissions when asked

USAGE:
- Click the bus icon in your menu bar
- Add routes by searching for stops
- Customize notification timing in settings

TROUBLESHOOTING:
If the app won't open:
- Make sure you used right-click → Open (not double-click)
- Check System Preferences → Security & Privacy → General
- Look for "KollektivWidget was blocked" and click "Open Anyway"

For more help: https://github.com/pederespen/kollektivwidget

EOF

# Create the ZIP file
echo "🗜️ Creating ZIP archive..."
cd "$ZIP_DIR"
zip -r "../$(basename "$ZIP_FILE")" . -x "*.DS_Store"
cd - > /dev/null

# Create convenience symlink
ln -sf "$(basename "$ZIP_FILE")" "$BUILD_DIR/${APP_NAME}.zip"

# Clean up
rm -rf "$ZIP_DIR"

echo "✅ ZIP distribution created!"
echo "📁 Output: $ZIP_FILE"
echo "📁 Symlink: $BUILD_DIR/${APP_NAME}.zip"
echo "📊 Size: $(ls -lh "$ZIP_FILE" | awk '{print $5}')"
echo ""
echo "🎉 Ready for distribution! Users can:"
echo "   1. Download and extract the ZIP"
echo "   2. Copy KollektivWidget.app to Applications"
echo "   3. Right-click → Open to bypass security warnings"
