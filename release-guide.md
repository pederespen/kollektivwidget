# Release Guide for KollektivWidget

This guide explains how to create and publish releases for KollektivWidget.

## Automated Release (Recommended)

The easiest way to create a release is using Git tags, which will automatically trigger the GitHub Actions workflow:

### 1. Create and Push a Version Tag

```bash
# Update version in KollektivWidget/Info.plist if needed
# Then create and push a tag
git tag v1.0.2
git push origin v1.0.2
```

The GitHub Actions workflow will automatically:
- Build the app
- Create a DMG package
- Create a GitHub release
- Upload the DMG as a release asset

## Manual Release

If you prefer to create releases manually:

### 1. Build the DMG locally

```bash
make release
```

This will create:
- `build/KollektivWidget-v{version}.dmg` - Versioned DMG file
- `build/KollektivWidget.dmg` - Symlink to the versioned DMG

### 2. Create GitHub Release Manually

1. Go to your GitHub repository
2. Click "Releases" → "Create a new release"
3. Create a new tag (e.g., `v1.0.2`)
4. Fill in the release title and description
5. Upload the DMG file from `build/KollektivWidget.dmg`
6. Publish the release

## Version Management

The version is controlled by the `CFBundleShortVersionString` in `KollektivWidget/Info.plist`:

```xml
<key>CFBundleShortVersionString</key>
<string>1.0.1</string>
```

Update this before creating releases to ensure proper versioning.

## Release Checklist

Before creating a release:

- [ ] Test the app thoroughly
- [ ] Update version in `Info.plist`
- [ ] Update `README.md` if needed
- [ ] Commit all changes
- [ ] Test DMG creation: `make dmg`
- [ ] Create and push version tag
- [ ] Verify release creation on GitHub
- [ ] Test download and installation

## Distribution Notes

The generated DMG includes:
- Properly signed app bundle (ad-hoc signature)
- Applications folder shortcut for easy installation
- Custom volume icon using app icon
- Optimized file size with compression

Users can install by:
1. Downloading the DMG
2. Opening it and dragging the app to Applications
3. Launching from Applications folder
4. Granting notification permissions when prompted
