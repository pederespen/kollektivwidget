# 🚌 Ruter Widget

macOS menu bar app that notifies you before your bus, tram, metro, or train departs.

## 🚀 Development quick start

### Prerequisites
- macOS 13+
- Xcode Command Line Tools: `xcode-select --install`

### Build, sign, install, and run

The Makefile handles everything (including ad‑hoc code signing so notifications work on macOS 15/Sequoia):

```bash
git clone <your-repo>
cd ruter-widget

# Rebuilds, ad‑hoc signs, installs to /Applications, and launches
make run

# If you need a fresh install
make reinstall

# Verify the app bundle is signed
make verify-sign

# Clean local build artifacts
make clean
```

On first launch, macOS will prompt for notification permission. Allow it. The app will then appear in System Settings > Notifications.

### Troubleshooting notifications (Sequoia)
- Always run the installed app from `/Applications` (the Makefile does this).
- The build is ad‑hoc signed automatically; this is sufficient for local development.
- If the app doesn’t appear under Settings > Notifications after allowing:
  - Quit the app, run `make reinstall`, launch again.
  - Restart your Mac once if needed.

## 🧭 Using the app
- Click the bus icon in the menu bar.
- Search a stop by name and select lines to monitor, or enter a stop ID (`NSR:StopPlace:XXXXX`).
- Set the notification lead time (default 5 min).
- Use “Test Notification” to confirm delivery.

## 🔧 Tech
- Swift, SwiftUI, Cocoa
- Entur Journey Planner GraphQL (public, no auth)
- Menubar app with background polling

## 📄 License
MIT
