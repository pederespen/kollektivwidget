#!/bin/bash

# DMG Creation Script for KollektivWidget
# This script creates a distributable DMG file for macOS

set -e

APP_NAME="KollektivWidget"
DMG_NAME="KollektivWidget"
BUILD_DIR="build"
DMG_DIR="$BUILD_DIR/dmg"
TEMP_DMG="$BUILD_DIR/${DMG_NAME}-temp.dmg"
FINAL_DMG="$BUILD_DIR/${DMG_NAME}.dmg"

# Get version from Info.plist or use current date
if [ -f "KollektivWidget/Info.plist" ]; then
    VERSION=$(defaults read "$(pwd)/KollektivWidget/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
else
    VERSION="1.0"
fi

VERSIONED_DMG="$BUILD_DIR/${DMG_NAME}-v${VERSION}.dmg"

echo "🚀 Creating DMG for $APP_NAME v$VERSION..."

# Clean up any existing DMG files
rm -f "$TEMP_DMG" "$FINAL_DMG" "$VERSIONED_DMG"
rm -rf "$DMG_DIR"

# Build the app first
echo "📦 Building application..."
make clean build

# Create DMG staging directory
mkdir -p "$DMG_DIR"

# Copy the app bundle to DMG directory
echo "📋 Copying app bundle..."
cp -R "$BUILD_DIR/$APP_NAME.app" "$DMG_DIR/"

# Create a symbolic link to Applications folder
echo "🔗 Creating Applications symlink..."
ln -s /Applications "$DMG_DIR/Applications"

# Create a background image for the DMG (if you have one)
DMG_BACKGROUND="dmg-background.png"
if [ -f "$DMG_BACKGROUND" ]; then
    mkdir -p "$DMG_DIR/.background"
    cp "$DMG_BACKGROUND" "$DMG_DIR/.background/"
fi

# Calculate size needed for DMG
echo "📏 Calculating DMG size..."
SIZE=$(du -sm "$DMG_DIR" | awk '{print $1}')
SIZE=$((SIZE + 50)) # Add 50MB padding

# Create temporary DMG
echo "💿 Creating temporary DMG..."
hdiutil create -srcfolder "$DMG_DIR" \
    -volname "$DMG_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size ${SIZE}m \
    "$TEMP_DMG"

# Mount the DMG for customization
echo "🔧 Mounting DMG for customization..."
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG" | egrep '^/dev/' | sed 1q | awk '{print $1}')
MOUNT_POINT="/Volumes/$DMG_NAME"

# Wait for mount
sleep 2

# Customize the DMG window appearance using AppleScript
echo "🎨 Customizing DMG appearance..."
if [ -f "$DMG_BACKGROUND" ]; then
    # With background image
    osascript << EOF
tell application "Finder"
    tell disk "$DMG_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 900, 450}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        set background picture of viewOptions to file ".background:$DMG_BACKGROUND"
        
        -- Position icons
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {350, 200}
        
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF
else
    # Without background image
    osascript << EOF
tell application "Finder"
    tell disk "$DMG_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 900, 450}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 100
        
        -- Position icons
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {350, 200}
        
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF
fi

# Set custom icon for the DMG volume (using app icon if available)
if [ -f "$BUILD_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns" ]; then
    echo "🎯 Setting custom volume icon..."
    cp "$BUILD_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_POINT/.VolumeIcon.icns"
    SetFile -a C "$MOUNT_POINT"
fi

# Hide background folder
if [ -d "$MOUNT_POINT/.background" ]; then
    SetFile -a V "$MOUNT_POINT/.background"
fi

# Sync and unmount
echo "💾 Finalizing DMG..."
sync
hdiutil detach "$DEVICE"

# Convert to final read-only DMG with compression
echo "🗜️ Compressing final DMG..."
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$VERSIONED_DMG"

# Clean up
rm -f "$TEMP_DMG"
rm -rf "$DMG_DIR"

# Create a symlink without version for convenience
ln -sf "$(basename "$VERSIONED_DMG")" "$FINAL_DMG"

echo "✅ DMG created successfully!"
echo "📁 Output: $VERSIONED_DMG"
echo "📁 Symlink: $FINAL_DMG"
echo "📊 Size: $(ls -lh "$VERSIONED_DMG" | awk '{print $5}')"
echo ""
echo "🎉 Ready for distribution! Users can:"
echo "   1. Download and mount the DMG"
echo "   2. Drag $APP_NAME.app to Applications"
echo "   3. Launch from Applications folder"
