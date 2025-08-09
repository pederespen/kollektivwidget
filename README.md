# 🚌 Ruter Widget

A macOS menu bar app that sends notifications when your bus, tram, or metro is about to leave - perfect for knowing when to leave work!

## ✨ Features

- **Simple Setup**: Add your transit stops by ID
- **Smart Notifications**: Get notified X minutes before departure
- **Real-time Data**: Uses Entur's live departure API
- **Menu Bar Integration**: Unobtrusive menu bar icon
- **Multiple Stops**: Monitor several stops at once
- **Transport Types**: Supports buses 🚌, trams 🚋, metro 🚇, and trains 🚆

## 🚀 Quick Start

### Prerequisites

- macOS 13.0 or later
- Xcode (for building from source)

### Building & Running

1. **Clone & Build**:

   ```bash
   git clone <your-repo>
   cd ruter-widget
   swift build -c release
   ```

2. **Run the App**:

   ```bash
   .build/release/RuterWidget
   ```

3. **Setup**:
   - Click the bus icon in your menu bar
   - Add your stop IDs (see "Finding Stop IDs" below)
   - Set notification lead time (default: 5 minutes)
   - Test with "Test Notification" button

### Finding Stop IDs

Stop IDs follow the format `NSR:StopPlace:XXXXX`. You can find them:

1. **Entur.org**: Search for your stop and copy the ID from the URL
2. **Ruter App**: Look in stop details
3. **Common Examples**:
   - `NSR:StopPlace:58366` - Jernbanetorget (Oslo Central)
   - `NSR:StopPlace:58249` - Nationaltheatret
   - `NSR:StopPlace:6275` - Stortinget

## 🔧 How It Works

1. **Monitor**: App checks your stops every 30 seconds
2. **Calculate**: Determines time until next departures
3. **Notify**: Sends macOS notification when departure is within your lead time
4. **Example**: "🚌 Bus 74 to Mortensrud leaves in 5 minutes from Jernbanetorget"

## 🎯 Perfect For

- **Commuters**: Know exactly when to leave work
- **Students**: Never miss your bus/tram to campus
- **Visitors**: Stay on schedule while exploring Oslo
- **Anyone**: Using Oslo's excellent public transport system

## 📝 Configuration

Settings are saved automatically:

- **Stops**: Stored in UserDefaults
- **Lead Time**: 1-30 minutes (default: 5)
- **Notifications**: Requires permission on first run

## 🔧 Technical Details

- **Language**: Swift
- **Framework**: SwiftUI + Cocoa
- **API**: Entur GraphQL API (public, no auth needed)
- **Platform**: macOS 13.0+
- **Architecture**: Menu bar app with background monitoring

## 🛠 Development

Built as a Swift Package for easy development:

```bash
# Build
swift build

# Run
swift run

# Clean
swift package clean
```

## 📱 API Usage

Uses Entur's public GraphQL API:

- **Endpoint**: `https://api.entur.io/journey-planner/v3/graphql`
- **No Authentication**: Public departure data
- **Real-time**: Live departure information
- **Coverage**: All Norwegian public transport

## 🚧 Future Ideas

- [ ] Favorite lines/destinations filtering
- [ ] Historical departure analysis
- [ ] Widget Kit integration
- [ ] Multiple location profiles (home/work)
- [ ] Departure delay notifications

## 🙏 Credits

- **Entur**: For providing excellent public transport APIs
- **Ruter**: For Oslo's fantastic transit system

## 📄 License

MIT License - Feel free to adapt for your city's transit system!
