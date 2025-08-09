import SwiftUI
import UserNotifications
import os.log

struct ContentView: View {
    @State private var searchQuery = ""
    @State private var searchResults: [StopSearchResult] = []
    @State private var isSearching = false
    @State private var selectedStop: StopSearchResult?
    @State private var availableLines: [TransitLine] = []
    @State private var isLoadingLines = false
    @State private var leadTimeMinutes = 5
    @State private var monitoredLines: [TransitLine] = []
    @State private var searchTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 16) {
            Text("🚌 Ruter Widget")
                .font(.title2)
                .fontWeight(.bold)
            
            // Step 1: Search for stops
            if selectedStop == nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text("1. Search for a Stop")
                        .font(.headline)
                    
                    HStack {
                        TextField("Search stops (e.g., \"jernbanetorget\")", text: $searchQuery)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: searchQuery) { _ in
                                searchStopsWithDebounce()
                            }
                        
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    
                    // Search results
                    if !searchResults.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(searchResults) { result in
                                    Button(action: {
                                        selectStop(result)
                                    }) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(result.name)
                                                .font(.body)
                                                .foregroundColor(.primary)
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
                        .frame(maxHeight: 150)
                    }
                }
            }
            
            // Step 2: Show selected stop and available lines
            if let stop = selectedStop {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("2. Lines from \(stop.name)")
                                .font(.headline)
                            Text("Select lines to monitor")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("Change Stop") {
                            selectedStop = nil
                            availableLines = []
                            searchQuery = ""
                            searchResults = []
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    
                    if isLoadingLines {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading lines...")
                        }
                    } else if !availableLines.isEmpty {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(availableLines) { line in
                                    HStack {
                                        Button(action: {
                                            toggleLineMonitoring(line)
                                        }) {
                                            HStack {
                                                Image(systemName: isLineMonitored(line) ? "checkmark.circle.fill" : "circle")
                                                    .foregroundColor(isLineMonitored(line) ? .green : .gray)
                                                
                                                Text(line.displayName)
                                                    .font(.body)
                                                    .foregroundColor(.primary)
                                                
                                                Spacer()
                                            }
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                            .background(isLineMonitored(line) ? Color.green.opacity(0.1) : Color.gray.opacity(0.05))
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }
            
            // Step 3: Show monitored lines
            if !monitoredLines.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("3. Monitored Lines (\(monitoredLines.count))")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(monitoredLines) { line in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(line.displayName)
                                            .font(.body)
                                        Text("from \(line.stopName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Remove") {
                                        removeMonitoredLine(line)
                                    }
                                    .font(.caption)
                                    .foregroundColor(.red)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color.gray.opacity(0.05))
                                .cornerRadius(6)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }
            
            Spacer()
            
            // Settings and controls
            VStack(spacing: 12) {
                HStack {
                    Text("Notification Lead Time:")
                        .font(.subheadline)
                    Spacer()
                    Stepper("\(leadTimeMinutes) min", value: $leadTimeMinutes, in: 1...30)
                        .fixedSize()
                }
                
                HStack(spacing: 12) {
                    Button("Test Notification") {
                        sendTestNotification()
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                    
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .padding()
        .frame(width: 420, height: 600)
        .onAppear {
            loadSettings()
        }
        .onChange(of: leadTimeMinutes) { _ in
            saveSettings()
        }
    }
    
    private func selectStop(_ stop: StopSearchResult) {
        os_log("🔍 Selecting stop: %{public}@ (%{public}@)", log: OSLog.default, type: .default, stop.name, stop.id)
        selectedStop = stop
        searchResults = []
        isLoadingLines = true
        
        Task {
            do {
                os_log("🌐 Calling API for lines from %{public}@", log: OSLog.default, type: .default, stop.id)
                let lines = try await EnturAPI.getAvailableLines(stopId: stop.id, stopName: stop.name)
                os_log("✅ Got %d lines from API", log: OSLog.default, type: .default, lines.count)
                for line in lines {
                    os_log("  - %{public}@", log: OSLog.default, type: .default, line.displayName)
                }
                await MainActor.run {
                    os_log("🎯 About to update UI with %d lines", log: OSLog.default, type: .default, lines.count)
                    self.availableLines = lines
                    self.isLoadingLines = false
                    os_log("✅ UI updated, availableLines.count = %d", log: OSLog.default, type: .default, self.availableLines.count)
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
    
    private func toggleLineMonitoring(_ line: TransitLine) {
        if let index = monitoredLines.firstIndex(where: { $0.id == line.id }) {
            monitoredLines.remove(at: index)
        } else {
            monitoredLines.append(line)
        }
        saveSettings()
    }
    
    private func isLineMonitored(_ line: TransitLine) -> Bool {
        monitoredLines.contains { $0.id == line.id }
    }
    
    private func removeMonitoredLine(_ line: TransitLine) {
        monitoredLines.removeAll { $0.id == line.id }
        saveSettings()
    }
    
    private func searchStopsWithDebounce() {
        // Cancel previous search task
        searchTask?.cancel()
        
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        
        // Create new debounced search task
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
            
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
    
    private func loadSettings() {
        // Load monitored lines
        if let data = UserDefaults.standard.data(forKey: "monitoredLines"),
           let decoded = try? JSONDecoder().decode([TransitLine].self, from: data) {
            monitoredLines = decoded
        }
        leadTimeMinutes = UserDefaults.standard.object(forKey: "leadTimeMinutes") as? Int ?? 5
    }
    
    private func saveSettings() {
        if let encoded = try? JSONEncoder().encode(monitoredLines) {
            UserDefaults.standard.set(encoded, forKey: "monitoredLines")
        }
        UserDefaults.standard.set(leadTimeMinutes, forKey: "leadTimeMinutes")
    }
    
    private func sendTestNotification() {
        // First check if we have permission
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                if settings.authorizationStatus == .authorized {
                    let content = UNMutableNotificationContent()
                    content.title = "🚌 Ruter Widget"
                    content.body = "Test notification: Bus 74 to Mortensrud leaves in 5 minutes!"
                    content.sound = UNNotificationSound.default
                    
                    let request = UNNotificationRequest(identifier: "test-\(Date().timeIntervalSince1970)", content: content, trigger: nil as UNNotificationTrigger?)
                    UNUserNotificationCenter.current().add(request) { error in
                        if let error = error {
                            print("❌ Error sending test notification: \(error)")
                        } else {
                            print("✅ Test notification sent successfully")
                        }
                    }
                } else {
                    print("❌ Notifications not authorized. Status: \(settings.authorizationStatus.rawValue)")
                    
                    // Show alert to user
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
}
