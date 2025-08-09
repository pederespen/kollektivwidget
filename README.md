# KollektivWidget

A macOS menu bar app that notifies you before your bus, tram, metro, or train departs anywhere in Norway.

Uses the Entur API to provide real-time departure information for all Norwegian public transport operators.

## Installation

### Download Release (Recommended)

1. Download the latest `KollektivWidget-v*.dmg` from [Releases](https://github.com/pederespen/kollektivwidget/releases)
2. Open the DMG file and drag KollektivWidget.app to Applications
3. Launch from Applications folder
4. Grant notification permissions when prompted

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
- **Smart notifications** with customizable timing
- **Dark mode** support
- **Menu bar integration** for quick access
- **Automatic refresh** of departure data

## Development

### Build Commands

```bash
make build          # Build the app bundle
make run            # Build, install, and launch
make dmg            # Create distributable DMG package
make release        # Build and package for release
make clean          # Clean build artifacts
```

### Creating Releases

See [release-guide.md](release-guide.md) for detailed release instructions.

## License

MIT
