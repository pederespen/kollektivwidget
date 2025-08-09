# KollektivWidget

A macOS menu bar app that notifies you before your bus, tram, metro, or train departs anywhere in Norway.

Uses the Entur API to provide real-time departure information for all Norwegian public transport operators.

## Installation

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
make clean          # Clean build artifacts
make reinstall      # Clean rebuild and install
```

### Code Structure

- `KollektivWidget/main.swift` - App entry point
- `KollektivWidget/ContentView.swift` - Main UI and logic
- `KollektivWidget/EnturAPI.swift` - API integration for transit data
- `KollektivWidget/Info.plist` - App configuration
- `Makefile` - Build system

## License

MIT