import Cocoa
import SwiftUI
import UserNotifications

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var timer: Timer?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Set up status bar item first
        setupStatusBar()
        
        // Configure notifications
        UNUserNotificationCenter.current().delegate = self
        logBundleInfo()
        
        // Request notification permissions with a slight delay to ensure app is fully loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.requestNotificationAuthorization()
        }
        
        // Start monitoring departures
        startMonitoring()
    }
    
    private func requestNotificationAuthorization() {
        print("🚀 Requesting notification authorization...")
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            print("🔔 Permission request completed: granted=\(granted), error=\(error?.localizedDescription ?? "none")")
            
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                print("📱 Notification settings -> status: \(settings.authorizationStatus.rawValue), alert: \(settings.alertSetting.rawValue), sound: \(settings.soundSetting.rawValue)")
            }
            
            if granted {
                // Do nothing; real notifications will come from upcoming departures
            } else {
                print("❌ Permission denied - opening System Settings > Notifications")
                self.showNotificationPermissionAlert()
            }
        }
    }
    
    // Keep this around if we later want to try a pre-flight notification before requesting permissions
    // but it's not needed for registration.
    
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

    // Ensure notifications show while the app is active (banner/list)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .list, .sound]
    }

    private func logBundleInfo() {
        let bundleId = Bundle.main.bundleIdentifier ?? "(nil)"
        let bundlePath = Bundle.main.bundlePath
        print("📦 Bundle ID: \(bundleId)")
        print("📦 Bundle Path: \(bundlePath)")
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
                // Position popover at top of screen instead of relative to button
                if let screen = NSScreen.main {
                    let screenFrame = screen.visibleFrame
                    let popoverSize = NSSize(width: 460, height: 280)
                    let popoverFrame = NSRect(
                        x: screenFrame.maxX - popoverSize.width - 20,
                        y: screenFrame.maxY - popoverSize.height - 10,
                        width: popoverSize.width,
                        height: popoverSize.height
                    )
                    popover.show(relativeTo: NSRect(origin: popoverFrame.origin, size: .zero), of: NSApp.keyWindow?.contentView ?? button, preferredEdge: .minY)
                } else {
                    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                }
                
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
        // Load all saved routes
        guard let data = UserDefaults.standard.data(forKey: "savedRoutes"),
              let routes = try? JSONDecoder().decode([TransitLine].self, from: data) else {
            return
        }

        for route in routes {
            let lead = route.notificationLeadTime ?? 5
            await checkLine(line: route, leadTimeMinutes: lead)
        }
    }
    
    private func checkLine(line: TransitLine, leadTimeMinutes: Int) async {
        do {
            let departures = try await EnturAPI.getDeparturesForLine(line: line)
            
            for departure in departures {
                let alreadyNotified = hasAlreadyNotified(for: departure)
                if departure.shouldNotify(leadTimeMinutes: leadTimeMinutes) && !alreadyNotified {
                    await sendNotification(for: departure, line: line)
                }
            }
        } catch {
            print("Error fetching departures for line \(line.displayName): \(error)")
        }
    }
    
    private func sendNotification(for departure: Departure, line: TransitLine) async {
        let content = UNMutableNotificationContent()
        content.title = "Ruter Departure"
        content.body = "Line \(departure.line) to \(departure.destination) leaves in \(departure.minutesUntilDeparture()) minutes from \(line.stopName)"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("Bell.aiff"))
        
        // Use departure info as identifier to avoid duplicate notifications
        let identifier = notificationIdentifier(for: departure)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil as UNNotificationTrigger?)
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("Sent notification: \(content.body)")
            markNotified(identifier: identifier)
        } catch {
            print("Error sending notification: \(error)")
        }
    }

    // MARK: - Notification de-duplication
    private func notificationIdentifier(for departure: Departure) -> String {
        "\(departure.line)-\(departure.destination)-\(Int(departure.departureTime.timeIntervalSince1970))"
    }
    
    private func hasAlreadyNotified(for departure: Departure) -> Bool {
        let identifier = notificationIdentifier(for: departure)
        let set = notifiedSet()
        return set.contains(identifier)
    }
    
    private func markNotified(identifier: String) {
        var set = notifiedSet()
        set.insert(identifier)
        UserDefaults.standard.set(Array(set), forKey: "notifiedDepartures")
    }
    
    private func notifiedSet() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: "notifiedDepartures") ?? []
        // Keep set small by trimming anything older than ~6 hours via timestamp in id if present
        return Set(arr)
    }
}

// Shared structures
struct SavedStop: Codable, Identifiable {
    let id: String
    let name: String
}


