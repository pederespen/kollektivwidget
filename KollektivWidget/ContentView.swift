import SwiftUI
import os.log

struct ContentView: View {
    // Callback to update the status bar with a title and optional SF Symbol name
    var updateStatusBar: ((String, String?) -> Void)?
    
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
    
    // Dark mode state
    @AppStorage("isDarkMode") private var isDarkMode = false
    

    
    // (Launch at login removed)
    

    
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

    @State private var routeToDelete: TransitLine?
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bus")
                    Text("KollektivWidget")
                }
                .font(.title2)
                .fontWeight(.bold)
                Spacer()
                Button(action: { isPresentingAddRoute = true }) {
                    Image(systemName: "plus")
                }
                .help("Add Route")
                Button(action: { Task { await refreshAllDepartures() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh all routes")
                Button(action: { isDarkMode.toggle() }) {
                    Image(systemName: isDarkMode ? "sun.max" : "moon")
                }
                .help(isDarkMode ? "Switch to Light Mode" : "Switch to Dark Mode")
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
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(savedRoutes) { route in
                            routeRow(route)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: maxScrollHeight())
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
        .frame(width: 460, height: dynamicHeight())
        .background(isDarkMode ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear {
            loadSettings()
            updateStatusBarSummary()
            Task { 
                await refreshAllDepartures()
            }
        }
        .sheet(isPresented: $isPresentingAddRoute, onDismiss: {
            Task { await refreshAllDepartures() }
        }) {
            addRouteSheet
                .frame(width: 460, height: 320)
                .padding()
                .background(isDarkMode ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }


        .alert("Delete Route", isPresented: Binding<Bool>(
            get: { routeToDelete != nil },
            set: { if !$0 { routeToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { routeToDelete = nil }
            Button("Delete", role: .destructive) {
                if let route = routeToDelete {
                    Task { 
                        removeRoute(route)
                        await MainActor.run { routeToDelete = nil }
                    }
                }
            }
        } message: {
            if let route = routeToDelete {
                Text("Are you sure you want to delete the route \"\(route.displayName)\" from \(route.stopName)?")
            }
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
            Task { await refreshAllDepartures() }
        }
    }

    // MARK: - Route Row
    private func routeRow(_ route: TransitLine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Image(systemName: symbolName(for: route.transportMode))
                            .font(.system(size: 14))
                        Text(route.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    Text("from \(route.stopName)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { routeToDelete = route }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete route")
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
                            Text(minutes == 0 ? "Now" : "\(minutes)m")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundColor(.white)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.blue)
                                .cornerRadius(6)
                        }
                        Spacer()
                        if loadingRouteIds.contains(route.id) {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }
            }
            .padding(6)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(6)

        }
        .padding(8)
        .background(isDarkMode ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.98, green: 0.98, blue: 1.0))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(isDarkMode ? 0.3 : 0.15), lineWidth: 1)
        )
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
                            .onChange(of: searchQuery) { _, _ in 
                                Task { await searchStopsWithDebounce() }
                            }
                        if isSearching { ProgressView().scaleEffect(0.8) }
                    }
                    if !searchResults.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(searchResults) { result in
                                    Button(action: { 
                                        Task { await selectStop(result) }
                                    }) {
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
                                    Image(systemName: symbolName(for: tab)).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onAppear { if !addTabs.contains(selectedAddTab), let first = addTabs.first { selectedAddTab = first } }
                        } else if let only = addTabs.first {
                            Color.clear.frame(height: 1).onAppear { selectedAddTab = only }
                        }


                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(availableLines.filter { selectedAddTab.matches(line: $0) }) { line in
                                    Button(action: { 
                                        Task { await chooseLine(line) }
                                    }) {
                                        HStack(spacing: 10) {
                                            Image(systemName: symbolName(for: line.transportMode))
                                            Text(line.displayName)
                                            Spacer()
                                            Image(systemName: "plus")
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                        .background(Color.blue.opacity(0.08))
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
        savedRoutes.append(line)
        saveSettings()
        Task { await refreshDepartures(for: line) }
        // Reset and close sheet so the user sees the added route immediately
        selectedStop = nil
        availableLines = []
        searchQuery = ""
        searchResults = []
        isPresentingAddRoute = false
    }




    

    
    // Launch at Login removed

    @MainActor
    private func removeRoute(_ route: TransitLine) {
        savedRoutes.removeAll { $0.id == route.id }
        routeDepartures.removeValue(forKey: route.id)
        saveSettings()
        updateStatusBarSummary()
    }



    // MARK: - Persistence
    @MainActor
    func loadSettings() {
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
    func refreshAllDepartures() async {
        await MainActor.run { self.isRefreshingAll = true }
        defer { Task { await MainActor.run { self.isRefreshingAll = false } } }
        let routes = await MainActor.run { self.savedRoutes }
        for route in routes {
            await refreshDepartures(for: route)
        }
        await MainActor.run {
            self.lastUpdated = Date()
            self.updateStatusBarSummary()
        }
    }

    private func refreshDepartures(for route: TransitLine) async {
        _ = await MainActor.run { self.loadingRouteIds.insert(route.id) }
        do {
            let deps = try await EnturAPI.getDeparturesForLine(line: route)
            await MainActor.run {
                self.routeDepartures[route.id] = Array(deps.prefix(3))
                self.loadingRouteIds.remove(route.id)
                self.updateStatusBarSummary()
            }
        } catch {
            await MainActor.run {
                self.routeDepartures[route.id] = []
                self.loadingRouteIds.remove(route.id)
                self.updateStatusBarSummary()
            }
            print("Error fetching departures: \(error)")
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
        return orderedTabs().filter { presentModes.contains($0) }
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

    private func symbolName(for transportMode: String) -> String {
        switch transportMode.lowercased() {
        case "bus": return "bus"
        case "tram": return "tram"
        case "metro": return "tram.fill.tunnel"
        case "train": return "train.side.front.car"
        case "ferry": return "ferry"
        default: return "bus"
        }
    }

    private func symbolName(for tab: TransportModeTab) -> String {
        switch tab {
        case .bus: return "bus"
        case .tram: return "tram"
        case .metro: return "tram.fill.tunnel"
        case .train: return "train.side.front.car"
        case .ferry: return "ferry"
        case .all: return "square.grid.2x2"
        }
    }
    

    // MARK: - Dynamic Height Calculation
    private func dynamicHeight() -> CGFloat {
        let headerHeight: CGFloat = 50 // Title and buttons
        let footerHeight: CGFloat = 40 // Updated text and quit button
        let padding: CGFloat = 28 // Total vertical padding
        let emptyStateHeight: CGFloat = 60 // "No routes added yet" message
        
        if savedRoutes.isEmpty {
            return headerHeight + emptyStateHeight + footerHeight + padding
        }
        
        let routeCardHeight: CGFloat = 90 // Approximate height per route card
        let spacing: CGFloat = 8 // Spacing between cards
        let contentHeight = CGFloat(savedRoutes.count) * (routeCardHeight + spacing) - spacing
        
        // Minimum height for at least one card, maximum for 3 cards before scrolling
        let minContentHeight = routeCardHeight
        let maxContentHeight = 3 * routeCardHeight + 2 * spacing
        let actualContentHeight = min(max(contentHeight, minContentHeight), maxContentHeight)
        
        return headerHeight + actualContentHeight + footerHeight + padding
    }
    
    private func maxScrollHeight() -> CGFloat {
        // Maximum height for the scroll view content (3 cards worth)
        let routeCardHeight: CGFloat = 90
        let spacing: CGFloat = 8
        return 3 * routeCardHeight + 2 * spacing
    }
    
    // MARK: - Data Initialization
    private func initializeData() async {
        await MainActor.run {
            loadSettings()
            updateStatusBarSummary()
        }
        await refreshAllDepartures()
    }
    
    // MARK: - Status Bar Summary
    @MainActor
    func updateStatusBarSummary() {
        let now = Date()
        var nextDeparture: Departure?
        for deps in routeDepartures.values {
            for dep in deps {
                guard dep.departureTime >= now else { continue }
                if let current = nextDeparture {
                    if dep.departureTime < current.departureTime { nextDeparture = dep }
                } else {
                    nextDeparture = dep
                }
            }
        }
        if let dep = nextDeparture {
            let minutes = max(dep.minutesUntilDeparture(), 0)
            let timeText = minutes == 0 ? "Now" : "\(minutes)m"
            print("🔄 Updating status bar: \(timeText) with icon: \(symbolName(for: dep.transportMode))")
            updateStatusBar?(timeText, symbolName(for: dep.transportMode))
        } else {
            print("🔄 No departures found, showing default")
            updateStatusBar?("—", "bus")
        }
    }

}




