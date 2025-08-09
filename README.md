# KollektivWidget

A macOS menu bar app that notifies you before your bus, tram, metro, or train departs anywhere in Norway.

Uses the Entur API to provide real-time departure information for all Norwegian public transport operators.

## Installation

### Download Release (Recommended)

1. Download the latest `KollektivWidget-v*.zip` from [Releases](https://github.com/pederespen/kollektivwidget/releases)
2. Extract the ZIP file and copy KollektivWidget.app to Applications
3. **Important:** Right-click the app in Applications and select "Open" (don't double-click)
4. Click "Open" when macOS asks if you're sure you want to open it
5. Grant notification permissions when prompted

> **Security Note:** You may see a warning that "Apple cannot verify KollektivWidget is free of malware." This is normal for unsigned apps. Using right-click → Open safely bypasses this warning.

**System Requirements:** macOS 13.0 or later

### Build from Source

**Prerequisites:** macOS 13+ and Xcode Command Line Tools (`xcode-select --install`)

```bash
git clone https://github.com/pederespen/kollektivwidget
cd kollektiv-widget
make run
```

The app will build, install to `/Applications`, and launch automatically.

## Usage

1. Click the bus icon in your menu bar
2. Add routes by searching for stops
3. Set notification timing (default: 5 minutes before departure)
4. Grant notification permission when prompted

## Features

- **Real-time departures** for all Norwegian public transport
- **Notifications** with customizable timing
- **Menu bar integration** for quick access
- **Dark mode**

## Development

### Build Commands

```bash
make build          # Build the app bundle
make run            # Build, install, and launch
make zip            # Create distributable ZIP package
make release        # Build and package for release
make clean          # Clean build artifacts
```

## License

MIT
