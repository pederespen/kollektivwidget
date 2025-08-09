import SwiftUI
import UserNotifications

struct ContentView: View {
    @State private var newStopId = ""
    @State private var leadTimeMinutes = 5
    @State private var savedStops: [String] = []
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🚌 Ruter Widget")
                .font(.title2)
                .fontWeight(.bold)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Add Stop")
                    .font(.headline)
                
                HStack {
                    TextField("Stop ID (e.g., NSR:StopPlace:58366)", text: $newStopId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Add") {
                        addStop()
                    }
                    .disabled(newStopId.isEmpty)
                }
                
                Text("Find stop IDs at entur.org or in the Ruter app")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Notification Lead Time")
                    .font(.headline)
                
                HStack {
                    Stepper("\(leadTimeMinutes) minutes", value: $leadTimeMinutes, in: 1...30)
                    Spacer()
                }
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Saved Stops")
                    .font(.headline)
                
                if savedStops.isEmpty {
                    Text("No stops added yet")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(savedStops, id: \.self) { stop in
                        HStack {
                            Text(stop)
                                .font(.monospaced(.body)())
                            Spacer()
                            Button("Remove") {
                                removeStop(stop)
                            }
                            .foregroundColor(.red)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            Divider()
            
            Button("Test Notification") {
                sendTestNotification()
            }
            .buttonStyle(.borderedProminent)
            
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Text("v1.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 350, height: 400)
        .onAppear {
            loadSettings()
        }
        .onChange(of: leadTimeMinutes) { _ in
            saveSettings()
        }
    }
    
    private func addStop() {
        let trimmedStopId = newStopId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedStopId.isEmpty && !savedStops.contains(trimmedStopId) {
            savedStops.append(trimmedStopId)
            newStopId = ""
            saveSettings()
        }
    }
    
    private func removeStop(_ stop: String) {
        savedStops.removeAll { $0 == stop }
        saveSettings()
    }
    
    private func loadSettings() {
        savedStops = UserDefaults.standard.array(forKey: "savedStops") as? [String] ?? []
        leadTimeMinutes = UserDefaults.standard.object(forKey: "leadTimeMinutes") as? Int ?? 5
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(savedStops, forKey: "savedStops")
        UserDefaults.standard.set(leadTimeMinutes, forKey: "leadTimeMinutes")
    }
    
    private func sendTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🚌 Ruter Widget"
        content.body = "Test notification: Bus 74 to Mortensrud leaves in 5 minutes!"
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: "test", content: content, trigger: nil as UNNotificationTrigger?)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending test notification: \(error)")
            }
        }
    }
}
