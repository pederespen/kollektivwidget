import SwiftUI
import UserNotifications
import os.log

struct ContentView: View {
    // Filtering tabs
    private enum TransportModeTab: String, CaseIterable, Identifiable {
        case all, metro, tram, bus, train, ferry
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All"
            case .metro: return "Metro"
            case .tram: return "Tram"
            case .bus: return "Bus"
            case .train: return "Train"
            case .ferry: return "Ferry"
            }
        }
        func matches(line: TransitLine) -> Bool {
            guard self != .all else { return true }
            return line.transportMode.lowercased() == self.rawValue
        }
    }
    // Saved routes state
    @State private var savedRoutes: [TransitLine] = []
    @State private var routeDepartures: [String: [Departure]] = [:]
    @State private var isRefreshingAll = false
    @State private var loadingRouteIds: Set<String> = []
    @State private var lastUpdated: Date? = nil

    // Add Route sheet state
    @State private var isPresentingAddRoute = false
    @State private var searchQuery = ""
    @State private var searchResults: [StopSearchResult] = []
    @State private var isSearching = false
    @State private var selectedStop: StopSearchResult?
    @State private var availableLines: [TransitLine] = []
    @State private var isLoadingLines = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedAddTab: TransportModeTab = .all
    @State private var addLeadTime: Int = 5
    @State private var routeBeingEdited: TransitLine?
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("🚌 Ruter Widget")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                if isRefreshingAll {
                    ProgressView().scaleEffect(0.9)
                } else {
                    Button(action: { Task { await refreshAllDepartures() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh all routes")
                }
                Button("Add Route") { isPresentingAddRoute = true }
                    .buttonStyle(.borderedProminent)
            }

            if savedRoutes.isEmpty {
                VStack(spacing: 8) {
                    Text("No routes added yet")
                        .foregroundColor(.secondary)
                    Text("Click Add Route to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(savedRoutes) { route in
                            routeRow(route)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: 12) {
                Text("Updated: \(lastUpdatedText())")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 460, height: 560)
        .onAppear {
            loadSettings()
            Task { await refreshAllDepartures() }
        }
        .sheet(isPresented: $isPresentingAddRoute, onDismiss: {
            Task { await refreshAllDepartures() }
        }) {
            addRouteSheet
                .frame(width: 460, height: 560)
                .padding()
        }
        .sheet(item: $routeBeingEdited) { route in
            editRouteSheet(route)
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
            Task { await refreshAllDepartures() }
        }
    }

    // MARK: - Route Row
    private func routeRow(_ route: TransitLine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.displayName)
                        .font(.headline)
                    Text("from \(route.stopName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Edit") { routeBeingEdited = route }
                    .buttonStyle(.borderless)
            }

            // Next departures as compact minute cards
            let deps = routeDepartures[route.id] ?? []
            VStack(alignment: .leading, spacing: 6) {
                if deps.isEmpty {
                    Text("No upcoming departures found")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    HStack(spacing: 8) {
                        ForEach(Array(deps.prefix(3).enumerated()), id: \.offset) { _, dep in
                            let minutes = max(dep.minutesUntilDeparture(), 0)
                            Text("\(minutes)m")
                                .font(.headline)
                                .monospacedDigit()
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(8)
                        }
                        Spacer()
                        if loadingRouteIds.contains(route.id) {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }
            }
            .padding(8)
            .background(Color.gray.opacity(0.06))
            .cornerRadius(8)

        }
        .padding(10)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(8)
    }

    // MARK: - Add Route Flow
    private var addRouteSheet: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Add Route")
                    .font(.headline)
                Spacer()
                Button("Close") { isPresentingAddRoute = false }
                    .buttonStyle(.borderless)
            }

            if selectedStop == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Search for a Stop")
                        .font(.subheadline)
                    HStack {
                        TextField("Search stops (e.g., \"jernbanetorget\")", text: $searchQuery)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: searchQuery) { _, _ in searchStopsWithDebounce() }
                        if isSearching { ProgressView().scaleEffect(0.8) }
                    }
                    if !searchResults.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(searchResults) { result in
                                    Button(action: { selectStop(result) }) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.name)
                                            Text(result.label)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 10)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .frame(maxHeight: 240)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("2. Choose a line from \(selectedStop?.name ?? "")")
                            .font(.subheadline)
                        Spacer()
                        Button("Change Stop") {
                            selectedStop = nil
                            availableLines = []
                            searchQuery = ""
                            searchResults = []
                        }
                        .font(.caption)
                    }
                    if isLoadingLines {
                        HStack { ProgressView().scaleEffect(0.8); Text("Loading lines...") }
                    } else if !availableLines.isEmpty {
                        let addTabs = tabsForAvailableLines()
                        if addTabs.count > 1 {
                            Picker("", selection: $selectedAddTab) {
                                ForEach(addTabs) { tab in
                                    Text(tab.title).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onAppear { if !addTabs.contains(selectedAddTab) { selectedAddTab = .all } }
                        } else {
                            Color.clear.frame(height: 1).onAppear { selectedAddTab = .all }
                        }

                        HStack {
                            Text("Notify before:")
                            Spacer()
                            Stepper("\(addLeadTime) min", onIncrement: {
                                addLeadTime = min(addLeadTime + 1, 30)
                            }, onDecrement: {
                                addLeadTime = max(addLeadTime - 1, 1)
                            })
                            .fixedSize()
                        }
                        .padding(.vertical, 4)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(availableLines.filter { selectedAddTab.matches(line: $0) }) { line in
                                    Button(action: { chooseLine(line) }) {
                                            HStack {
                                                Text(line.displayName)
                                                Spacer()
                                            Image(systemName: "plus.circle")
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                        .background(Color.gray.opacity(0.06))
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                }
            }
            Spacer()
        }
        .onAppear { addLeadTime = 5 }
    }
    
    @MainActor
    private func selectStop(_ stop: StopSearchResult) {
        os_log("🔍 Selecting stop: %{public}@ (%{public}@)", log: OSLog.default, type: .default, stop.name, stop.id)
        selectedStop = stop
        searchResults = []
        isLoadingLines = true
        
        Task {
            do {
                let lines = try await EnturAPI.getAvailableLines(stopId: stop.id, stopName: stop.name)
                await MainActor.run {
                    self.availableLines = lines
                    self.isLoadingLines = false
                }
            } catch {
                await MainActor.run {
                    self.availableLines = []
                    self.isLoadingLines = false
                }
                os_log("❌ Error loading lines: %{public}@", log: OSLog.default, type: .error, error.localizedDescription)
            }
        }
    }
    
    @MainActor
    private func chooseLine(_ line: TransitLine) {
        // Prevent duplicates
        guard !savedRoutes.contains(where: { $0.id == line.id }) else { return }
        var newLine = line
        newLine.notificationLeadTime = addLeadTime
        savedRoutes.append(newLine)
        saveSettings()
        Task { await refreshDepartures(for: newLine) }
        // Reset and close sheet so the user sees the added route immediately
        selectedStop = nil
        availableLines = []
        searchQuery = ""
        searchResults = []
        isPresentingAddRoute = false
    }

    // MARK: - Edit Route Sheet
    private func editRouteSheet(_ route: TransitLine) -> some View {
        EditRouteSheetView(
            route: route,
            initialLeadTime: effectiveLeadTime(for: route),
            onSave: { minutes in
                updateLeadTime(for: route, to: minutes)
                routeBeingEdited = nil
            },
            onDelete: {
                removeRoute(route)
                routeBeingEdited = nil
            },
            onClose: { routeBeingEdited = nil }
        )
        .frame(width: 360, height: 220)
        .padding()
    }

    @MainActor
    private func removeRoute(_ route: TransitLine) {
        savedRoutes.removeAll { $0.id == route.id }
        routeDepartures.removeValue(forKey: route.id)
        saveSettings()
    }

    @MainActor
    private func updateLeadTime(for route: TransitLine, to minutes: Int) {
        guard let idx = savedRoutes.firstIndex(where: { $0.id == route.id }) else { return }
        savedRoutes[idx].notificationLeadTime = minutes
        saveSettings()
    }

    // MARK: - Persistence
    @MainActor
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: "savedRoutes"),
           let decoded = try? JSONDecoder().decode([TransitLine].self, from: data) {
            savedRoutes = decoded
        } else if let legacy = UserDefaults.standard.data(forKey: "monitoredLines"),
                  let decoded = try? JSONDecoder().decode([TransitLine].self, from: legacy) {
            savedRoutes = decoded
            saveSettings()
        }
    }

    @MainActor
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(savedRoutes) {
            UserDefaults.standard.set(encoded, forKey: "savedRoutes")
        }
    }

    // MARK: - Departures
    private func refreshAllDepartures() async {
        await MainActor.run { self.isRefreshingAll = true }
        defer { Task { await MainActor.run { self.isRefreshingAll = false } } }
        let routes = await MainActor.run { self.savedRoutes }
        for route in routes {
            await refreshDepartures(for: route)
        }
        await MainActor.run { self.lastUpdated = Date() }
    }

    private func refreshDepartures(for route: TransitLine) async {
        _ = await MainActor.run { self.loadingRouteIds.insert(route.id) }
        do {
            let deps = try await EnturAPI.getDeparturesForLine(line: route)
            await MainActor.run {
                self.routeDepartures[route.id] = Array(deps.prefix(3))
                self.loadingRouteIds.remove(route.id)
            }
        } catch {
            await MainActor.run {
                self.routeDepartures[route.id] = []
                self.loadingRouteIds.remove(route.id)
            }
            print("Error fetching departures: \(error)")
        }
    }

    // MARK: - Test Notification
    private func sendTestNotification() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .authorized {
                    let content = UNMutableNotificationContent()
                    content.title = "🚌 Ruter Widget"
                    content.body = "Test notification: Bus 74 to Mortensrud leaves in 5 minutes!"
                    content.sound = UNNotificationSound.default
                    let request = UNNotificationRequest(
                        identifier: "test-\(Date().timeIntervalSince1970)",
                        content: content,
                        trigger: nil as UNNotificationTrigger?
                    )
                    UNUserNotificationCenter.current().add(request) { error in
                        if let error = error {
                            print("❌ Error sending test notification: \(error)")
                        } else {
                            print("✅ Test notification sent successfully")
                        }
                    }
                } else {
                    let alert = NSAlert()
                    alert.messageText = "Notifications Not Allowed"
                    alert.informativeText = "Please enable notifications for Ruter Widget in System Preferences > Notifications to receive departure alerts."
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                }
            }
        }
    }
    
    @MainActor
    private func searchStopsWithDebounce() {
        searchTask?.cancel()
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            do {
                let results = try await EnturAPI.searchStops(query: searchQuery)
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.searchResults = []
                    self.isSearching = false
                }
                print("Error searching stops: \(error)")
            }
        }
    }
    
    private func effectiveLeadTime(for route: TransitLine) -> Int {
        route.notificationLeadTime ?? 5
    }

    private func lastUpdatedText() -> String {
        guard let ts = lastUpdated else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: ts)
    }

    // MARK: - Tabs helpers
    private func tabsForSavedRoutes() -> [TransportModeTab] {
        var presentModes: Set<TransportModeTab> = []
        for route in savedRoutes {
            if let tab = tabFor(modeString: route.transportMode) { presentModes.insert(tab) }
        }
        var result: [TransportModeTab] = [.all]
        result.append(contentsOf: orderedTabs().filter { presentModes.contains($0) })
        return result
    }

    private func tabsForAvailableLines() -> [TransportModeTab] {
        var presentModes: Set<TransportModeTab> = []
        for line in availableLines {
            if let tab = tabFor(modeString: line.transportMode) { presentModes.insert(tab) }
        }
        var result: [TransportModeTab] = [.all]
        result.append(contentsOf: orderedTabs().filter { presentModes.contains($0) })
        return result
    }

    private func tabFor(modeString: String) -> TransportModeTab? {
        switch modeString.lowercased() {
        case "metro": return .metro
        case "tram": return .tram
        case "bus": return .bus
        case "train": return .train
        case "ferry": return .ferry
        default: return nil
        }
    }

    private func orderedTabs() -> [TransportModeTab] {
        [.metro, .tram, .bus, .train, .ferry]
    }
}

// MARK: - Edit Route Sheet View
struct EditRouteSheetView: View {
    let route: TransitLine
    let initialLeadTime: Int
    let onSave: (Int) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @State private var leadTime: Int = 5

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Edit Route")
                    .font(.headline)
                Spacer()
                Button("Close") { onClose() }
                    .buttonStyle(.borderless)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(route.displayName)
                    .font(.headline)
                Text("from \(route.stopName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Notify before:")
                Spacer()
                Stepper("\(leadTime) min", onIncrement: {
                    leadTime = min(leadTime + 1, 30)
                }, onDecrement: {
                    leadTime = max(leadTime - 1, 1)
                })
                .fixedSize()
            }

            Spacer()

            HStack {
                Button("Delete") { onDelete() }
                    .foregroundColor(.red)
                Spacer()
                Button("Cancel") { onClose() }
                Button("Save") { onSave(leadTime) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { leadTime = initialLeadTime }
    }
}
