import SwiftUI
import UserNotifications
import os.log
import ServiceManagement

struct ContentView: View {
    // Callback for updating menu bar icon
    var updateMenuBarIcon: ((Bool) -> Void)?
    
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
    
    // Notification settings
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("notificationStartHour") private var notificationStartHour = 8
    @AppStorage("notificationStartMinute") private var notificationStartMinute = 0
    @AppStorage("notificationEndHour") private var notificationEndHour = 17
    @AppStorage("notificationEndMinute") private var notificationEndMinute = 0
    
    // Launch at login setting
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    
    // Weekday notification settings (1=Sunday, 2=Monday, ..., 7=Saturday)
    @State private var selectedWeekdays: Set<Int> = [2, 3, 4, 5, 6] // Monday-Friday default
    
    // Notification status for UI indicators
    @State private var notificationStatus: NotificationStatus = .enabled
    
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
    @State private var routeToDelete: TransitLine?
    @State private var isPresentingSettings = false
    
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "bus")
                    Text("Ruter Widget")
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
                Button(action: { isPresentingSettings = true }) {
                    Image(systemName: "gear")
                }
                .help("Settings")
            }
            
            // Notification status indicator
            HStack(spacing: 8) {
                Image(systemName: notificationStatus.iconName)
                    .foregroundColor(notificationStatus.statusColor)
                    .font(.system(size: 12, weight: .medium))
                Text(notificationStatus.statusText)
                    .font(.caption)
                    .foregroundColor(notificationStatus.statusColor)
                Spacer()
                if !notificationStatus.isEnabled {
                    Button("Settings") {
                        isPresentingSettings = true
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(notificationStatus.statusColor.opacity(0.1))
            .cornerRadius(6)

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
        .frame(width: 460, height: 280)
        .background(isDarkMode ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 2)
        .preferredColorScheme(isDarkMode ? .dark : .light)
        .onAppear {
            loadSettings()
            loadWeekdaySettings()
            checkLaunchAtLoginStatus()
            updateNotificationStatus()
            Task { await refreshAllDepartures() }
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
        .sheet(item: $routeBeingEdited) { route in
            editRouteSheet(route)
                .background(isDarkMode ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
                .preferredColorScheme(isDarkMode ? .dark : .light)
        }
        .sheet(isPresented: $isPresentingSettings) {
            settingsSheet
                .frame(width: 400)
                .padding()
                .background(isDarkMode ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white)
                .preferredColorScheme(isDarkMode ? .dark : .light)
                .fixedSize(horizontal: false, vertical: true)
        }
        .alert("Delete Route", isPresented: Binding<Bool>(
            get: { routeToDelete != nil },
            set: { if !$0 { routeToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { routeToDelete = nil }
            Button("Delete", role: .destructive) {
                if let route = routeToDelete {
                    removeRoute(route)
                    routeToDelete = nil
                }
            }
        } message: {
            if let route = routeToDelete {
                Text("Are you sure you want to delete the route \"\(route.displayName)\" from \(route.stopName)?")
            }
        }
        .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
            updateNotificationStatus()
            Task { await refreshAllDepartures() }
        }
        .onChange(of: notificationsEnabled) { _, _ in updateNotificationStatus() }
        .onChange(of: notificationStartHour) { _, _ in updateNotificationStatus() }
        .onChange(of: notificationStartMinute) { _, _ in updateNotificationStatus() }
        .onChange(of: notificationEndHour) { _, _ in updateNotificationStatus() }
        .onChange(of: notificationEndMinute) { _, _ in updateNotificationStatus() }
        .onChange(of: selectedWeekdays) { _, _ in updateNotificationStatus() }
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
                HStack(spacing: 2) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("\(effectiveLeadTime(for: route))min")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: 4) {
                    Button(action: { routeBeingEdited = route }) {
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .help("Edit route")
                    
                    Button(action: { routeToDelete = route }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete route")
                }
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
                                    Image(systemName: symbolName(for: tab)).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onAppear { if !addTabs.contains(selectedAddTab), let first = addTabs.first { selectedAddTab = first } }
                        } else if let only = addTabs.first {
                            Color.clear.frame(height: 1).onAppear { selectedAddTab = only }
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

    // MARK: - Settings Sheet
    private var settingsSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Close") { isPresentingSettings = false }
                    .buttonStyle(.borderless)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Dark Mode")
                        .font(.subheadline)
                    Spacer()
                    Toggle("", isOn: $isDarkMode)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                Divider()
                
                HStack {
                    Text("Launch at Login")
                        .font(.subheadline)
                    Spacer()
                    Toggle("", isOn: $launchAtLogin)
                        .toggleStyle(SwitchToggleStyle())
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(enabled: newValue)
                        }
                }
                
                Divider()
                
                HStack {
                    Text("Notifications")
                        .font(.subheadline)
                    Spacer()
                    Toggle("", isOn: $notificationsEnabled)
                        .toggleStyle(SwitchToggleStyle())
                }
                
                if notificationsEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Hours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("From:")
                                .font(.caption)
                            
                            HStack(spacing: 4) {
                                Picker("", selection: $notificationStartHour) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(String(format: "%02d", hour)).tag(hour)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 60)
                                
                                Text(":")
                                
                                Picker("", selection: $notificationStartMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                                        Text(String(format: "%02d", minute)).tag(minute)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 60)
                            }
                            
                            Spacer()
                            
                            Text("To:")
                                .font(.caption)
                            
                            HStack(spacing: 4) {
                                Picker("", selection: $notificationEndHour) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(String(format: "%02d", hour)).tag(hour)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 60)
                                
                                Text(":")
                                
                                Picker("", selection: $notificationEndMinute) {
                                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                                        Text(String(format: "%02d", minute)).tag(minute)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 60)
                            }
                        }
                    }
                    .padding(.leading, 16)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                            ForEach(weekdayData, id: \.value) { weekday in
                                Button(action: { toggleWeekday(weekday.value) }) {
                                    Text(weekday.short)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(selectedWeekdays.contains(weekday.value) ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .background(selectedWeekdays.contains(weekday.value) ? Color.blue : Color.gray.opacity(0.2))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.leading, 16)
                }
                
                Divider()
                
                HStack {
                    Text("App Version")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("1.0.0")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Weekday Management
    private var weekdayData: [(short: String, value: Int)] {
        [
            ("Mon", 2), ("Tue", 3), ("Wed", 4), ("Thu", 5),
            ("Fri", 6), ("Sat", 7), ("Sun", 1)
        ]
    }
    
    private func toggleWeekday(_ weekday: Int) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
        saveWeekdaySettings()
    }
    
    private func loadWeekdaySettings() {
        if let data = UserDefaults.standard.data(forKey: "selectedWeekdays"),
           let weekdays = try? JSONDecoder().decode([Int].self, from: data) {
            selectedWeekdays = Set(weekdays)
        } else {
            // Default to Monday-Friday
            selectedWeekdays = [2, 3, 4, 5, 6]
            saveWeekdaySettings()
        }
    }
    
    private func saveWeekdaySettings() {
        if let data = try? JSONEncoder().encode(Array(selectedWeekdays)) {
            UserDefaults.standard.set(data, forKey: "selectedWeekdays")
        }
    }
    
    // MARK: - Launch at Login
    private func checkLaunchAtLoginStatus() {
        if #available(macOS 13.0, *) {
            // Check current status using SMAppService and sync our UI
            let isRegistered = SMAppService.mainApp.status == .enabled
            // Only update UI if there's a mismatch (avoid infinite loops)
            if launchAtLogin != isRegistered {
                // Don't automatically revert - let user's last action stand
                // This prevents the toggle from fighting with the system state
                print("📍 Launch at login status mismatch: UI=\(launchAtLogin), System=\(isRegistered)")
            }
        }
        // For older macOS versions, we rely on the stored preference
        // since there's no reliable way to check the current status
    }
    
    private func setLaunchAtLogin(enabled: Bool) {
        if #available(macOS 13.0, *) {
            // Use modern SMAppService for macOS 13+
            do {
                if enabled {
                    if SMAppService.mainApp.status == .notRegistered {
                        try SMAppService.mainApp.register()
                        print("✅ Registered app for launch at login")
                    } else {
                        print("📍 App already registered for launch at login")
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        print("✅ Unregistered app from launch at login")
                    } else {
                        print("📍 App was not registered for launch at login")
                    }
                }
            } catch {
                print("❌ Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
                // Only revert if it's a critical error, not permission issues
                if (error as NSError).code != 1 { // Don't revert for permission denied
                    DispatchQueue.main.async {
                        self.launchAtLogin = !enabled
                    }
                }
            }
        } else {
            // Fallback for older macOS versions
            let success = SMLoginItemSetEnabled("com.pespen.ruterwidget" as CFString, enabled)
            if success {
                print("✅ \(enabled ? "Enabled" : "Disabled") launch at login (legacy)")
            } else {
                print("❌ Failed to \(enabled ? "enable" : "disable") launch at login (legacy)")
                // Only revert on actual failures, not permission issues
                DispatchQueue.main.async {
                    self.launchAtLogin = !enabled
                }
            }
        }
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
    
    // MARK: - Notification Status
    private func updateNotificationStatus() {
        notificationStatus = getCurrentNotificationStatus()
        updateMenuBarIcon?(notificationStatus.isEnabled)
    }
    
    private func getCurrentNotificationStatus() -> NotificationStatus {
        // Check if notifications are globally disabled
        guard notificationsEnabled else {
            return .disabled(reason: "Notifications disabled in settings")
        }
        
        // Get current time and weekday
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)
        
        // Check weekday settings
        if !selectedWeekdays.contains(currentWeekday) {
            let weekdayName = calendar.weekdaySymbols[currentWeekday - 1]
            return .disabled(reason: "Disabled on \(weekdayName)")
        }
        
        // Check time settings
        let currentMinutesSinceMidnight = currentHour * 60 + currentMinute
        let startMinutesSinceMidnight = notificationStartHour * 60 + notificationStartMinute
        let endMinutesSinceMidnight = notificationEndHour * 60 + notificationEndMinute
        
        let isWithinActiveHours: Bool
        if startMinutesSinceMidnight <= endMinutesSinceMidnight {
            isWithinActiveHours = currentMinutesSinceMidnight >= startMinutesSinceMidnight && 
                                  currentMinutesSinceMidnight <= endMinutesSinceMidnight
        } else {
            isWithinActiveHours = currentMinutesSinceMidnight >= startMinutesSinceMidnight || 
                                  currentMinutesSinceMidnight <= endMinutesSinceMidnight
        }
        
        if !isWithinActiveHours {
            let startTime = String(format: "%02d:%02d", notificationStartHour, notificationStartMinute)
            let endTime = String(format: "%02d:%02d", notificationEndHour, notificationEndMinute)
            return .disabled(reason: "Outside active hours (\(startTime) - \(endTime))")
        }
        
        return .enabled
    }
}

// MARK: - Notification Status Types
enum NotificationStatus: Equatable {
    case enabled
    case disabled(reason: String)
    
    var isEnabled: Bool {
        switch self {
        case .enabled: return true
        case .disabled: return false
        }
    }
    
    var iconName: String {
        switch self {
        case .enabled: return "bus"
        case .disabled: return "bell.slash"
        }
    }
    
    var statusText: String {
        switch self {
        case .enabled: return "Notifications active"
        case .disabled(let reason): return reason
        }
    }
    
    var statusColor: Color {
        switch self {
        case .enabled: return .green
        case .disabled: return .orange
        }
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
                Spacer()
                Button("Cancel") { onClose() }
                Button("Save") { onSave(leadTime) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .onAppear { leadTime = initialLeadTime }
    }
}
