#!/bin/bash

# Generate macOS app icons from source_icon.png
# This script uses sips (built into macOS) to resize with proper transparency

SOURCE_ICON="AppIcons/source_icon.png"
OUTPUT_DIR="RuterWidget/RuterWidget/Assets.xcassets/AppIcon.appiconset"

# Check if source icon exists
if [ ! -f "$SOURCE_ICON" ]; then
    echo "❌ Source icon not found: $SOURCE_ICON"
    exit 1
fi

echo "🎨 Generating macOS app icons from $SOURCE_ICON..."

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

# Generate all required sizes using sips (preserves transparency)
# macOS app icon sizes: 16, 32, 64, 128, 256, 512, 1024

echo "📐 Generating 16x16..."
sips -z 16 16 "$SOURCE_ICON" --out "$OUTPUT_DIR/16.png" > /dev/null

echo "📐 Generating 32x32..."
sips -z 32 32 "$SOURCE_ICON" --out "$OUTPUT_DIR/32.png" > /dev/null

echo "📐 Generating 64x64..."
sips -z 64 64 "$SOURCE_ICON" --out "$OUTPUT_DIR/64.png" > /dev/null

echo "📐 Generating 128x128..."
sips -z 128 128 "$SOURCE_ICON" --out "$OUTPUT_DIR/128.png" > /dev/null

echo "📐 Generating 256x256..."
sips -z 256 256 "$SOURCE_ICON" --out "$OUTPUT_DIR/256.png" > /dev/null

echo "📐 Generating 512x512..."
sips -z 512 512 "$SOURCE_ICON" --out "$OUTPUT_DIR/512.png" > /dev/null

echo "📐 Generating 1024x1024..."
sips -z 1024 1024 "$SOURCE_ICON" --out "$OUTPUT_DIR/1024.png" > /dev/null

echo "✅ Generated all icon sizes!"
echo "📁 Icons saved to: $OUTPUT_DIR"

# Verify generated files
echo "🔍 Verifying generated icons..."
for size in 16 32 64 128 256 512 1024; do
    if [ -f "$OUTPUT_DIR/${size}.png" ]; then
        echo "  ✓ ${size}.png"
    else
        echo "  ❌ ${size}.png - MISSING"
    fi
done

echo ""
echo "🚀 Ready to rebuild! Run: make reinstall"
