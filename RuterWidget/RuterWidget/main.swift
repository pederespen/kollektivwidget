import Cocoa
import SwiftUI
import UserNotifications

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var timer: Timer?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Set up status bar item first
        setupStatusBar()
        
        // Request notification permissions with delay to ensure app is fully loaded  
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.forceNotificationRegistration()
        }
        
        // Start monitoring departures
        startMonitoring()
    }
    
    private func forceNotificationRegistration() {
        print("🚀 FORCE REGISTERING app with macOS notification system...")
        
        // Step 1: Request permissions - this should trigger the system dialog
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("🔔 Permission request completed: granted=\(granted), error=\(error?.localizedDescription ?? "none")")
            
            if granted {
                // Send a test notification immediately
                DispatchQueue.main.async {
                    self.sendImmediateTestNotification()
                }
            } else {
                print("❌ Permission denied - app should now appear in System Preferences")
            }
        }
    }
    
    private func sendImmediateTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "🎉 Success!"
        content.body = "Ruter Widget notifications are now working!"
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: "success-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Error sending success notification: \(error)")
            } else {
                print("✅ Success notification sent!")
            }
        }
    }
    
    private func requestNotificationPermission() {
        print("🔔 Forcing app registration with notification system...")
        
        // FIRST: Try to send a notification immediately to force registration
        let content = UNMutableNotificationContent()
        content.title = "🚌 Ruter Widget"
        content.body = "Registering with notification system..."
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: "register-\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            print("📝 Registration attempt result: \(error?.localizedDescription ?? "Success")")
            
            // THEN: Request permissions
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                DispatchQueue.main.async {
                    if granted {
                        print("✅ Notification permission granted")
                        
                        // Send a welcome notification to confirm it works
                        let welcomeContent = UNMutableNotificationContent()
                        welcomeContent.title = "🚌 Ruter Widget Ready!"
                        welcomeContent.body = "Notifications are now enabled. You'll get alerts for your chosen departure times."
                        welcomeContent.sound = UNNotificationSound.default
                        
                        let welcomeRequest = UNNotificationRequest(identifier: "welcome-\(Date().timeIntervalSince1970)", content: welcomeContent, trigger: nil)
                        UNUserNotificationCenter.current().add(welcomeRequest) { error in
                            if let error = error {
                                print("❌ Error sending welcome notification: \(error)")
                            } else {
                                print("✅ Welcome notification sent")
                            }
                        }
                        
                        // Check detailed settings
                        UNUserNotificationCenter.current().getNotificationSettings { settings in
                            print("📱 Notification settings: \(settings.authorizationStatus.rawValue)")
                            print("🔔 Alert setting: \(settings.alertSetting.rawValue)")
                            print("🔊 Sound setting: \(settings.soundSetting.rawValue)")
                        }
                    } else {
                        print("❌ Notification permission denied")
                        if let error = error {
                            print("   Error: \(error.localizedDescription)")
                        }
                        // Show an alert to guide user to System Preferences
                        self.showNotificationPermissionAlert()
                    }
                }
            }
        }
    }
    
    private func showNotificationPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Notifications Disabled"
            alert.informativeText = "To receive departure notifications, please enable notifications for Ruter Widget in System Preferences > Notifications."
            alert.addButton(withTitle: "Open System Preferences")
            alert.addButton(withTitle: "Cancel")
            
            if alert.runModal() == .alertFirstButtonReturn {
                // Open System Preferences to Notifications
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            }
        }
    }
    
    private func setupStatusBar() {
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusBarItem.button {
            button.image = NSImage(systemSymbolName: "bus", accessibilityDescription: "Ruter Widget")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create popover
        popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: ContentView())
        popover.behavior = .applicationDefined
        popover.animates = true
    }
    
    @objc private func togglePopover() {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.close()
            } else {
                // Activate app and show popover
                NSApp.activate(ignoringOtherApps: true)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                
                // Set up event monitor to close when clicking outside
                setupEventMonitor()
            }
        }
    }
    
    private func setupEventMonitor() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let popover = self?.popover, popover.isShown {
                popover.close()
            }
        }
    }
    
    private func startMonitoring() {
        // Check departures every 30 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task {
                await self.checkDepartures()
            }
        }
        
        // Initial check
        Task {
            await checkDepartures()
        }
    }
    
    private func checkDepartures() async {
        let leadTime = UserDefaults.standard.integer(forKey: "leadTimeMinutes")
        let effectiveLeadTime = leadTime > 0 ? leadTime : 5
        
        // Load monitored lines
        var monitoredLines: [TransitLine] = []
        if let data = UserDefaults.standard.data(forKey: "monitoredLines"),
           let decoded = try? JSONDecoder().decode([TransitLine].self, from: data) {
            monitoredLines = decoded
        }
        
        for line in monitoredLines {
            await checkLine(line: line, leadTimeMinutes: effectiveLeadTime)
        }
    }
    
    private func checkLine(line: TransitLine, leadTimeMinutes: Int) async {
        do {
            let departures = try await EnturAPI.getDeparturesForLine(line: line)
            
            for departure in departures {
                if departure.shouldNotify(leadTimeMinutes: leadTimeMinutes) {
                    await sendNotification(for: departure, line: line)
                }
            }
        } catch {
            print("Error fetching departures for line \(line.displayName): \(error)")
        }
    }
    
    private func sendNotification(for departure: Departure, line: TransitLine) async {
        let content = UNMutableNotificationContent()
        content.title = "\(line.transportEmoji) Ruter Departure"
        content.body = "Line \(departure.line) to \(departure.destination) leaves in \(departure.minutesUntilDeparture()) minutes from \(line.stopName)"
        content.sound = UNNotificationSound.default
        
        // Use departure info as identifier to avoid duplicate notifications
        let identifier = "\(departure.line)-\(departure.departureTime.timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil as UNNotificationTrigger?)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("Sent notification: \(content.body)")
        } catch {
            print("Error sending notification: \(error)")
        }
    }
}

// Shared structures
struct SavedStop: Codable, Identifiable {
    let id: String
    let name: String
}


