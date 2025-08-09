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
    var contentView: ContentView?
    
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
            alert.informativeText = "To receive departure notifications, please enable notifications for KollektivWidget in System Preferences > Notifications."
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
            button.image = NSImage(systemSymbolName: "bus", accessibilityDescription: "KollektivWidget")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Create popover
        popover = NSPopover()
        contentView = ContentView(updateMenuBarIcon: { [weak self] isEnabled in
            self?.updateMenuBarIcon(isNotificationEnabled: isEnabled)
        })
        popover.contentViewController = NSHostingController(rootView: contentView!)
        popover.behavior = .transient
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
            }
        }
    }
    
    func updateMenuBarIcon(isNotificationEnabled: Bool) {
        if let button = statusBarItem.button {
            // Use different symbols that definitely exist
            let iconName = isNotificationEnabled ? "bus" : "bell.slash"
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "KollektivWidget")
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
        // Check if notifications are enabled and within active hours
        guard shouldSendNotifications() else { return }
        
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
    
    private func shouldSendNotifications() -> Bool {
        // Check if notifications are enabled (default to true if not set)
        let notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        guard notificationsEnabled else {
            print("🔕 Notifications disabled - skipping")
            return false
        }
        
        // Get notification time settings (default to 8:00 - 17:00)
        let startHour = UserDefaults.standard.object(forKey: "notificationStartHour") as? Int ?? 8
        let startMinute = UserDefaults.standard.object(forKey: "notificationStartMinute") as? Int ?? 0
        let endHour = UserDefaults.standard.object(forKey: "notificationEndHour") as? Int ?? 17
        let endMinute = UserDefaults.standard.object(forKey: "notificationEndMinute") as? Int ?? 0
        
        // Get current time and weekday
        let now = Date()
        let calendar = Calendar.current
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let currentWeekday = calendar.component(.weekday, from: now)
        
        // Check if notifications are enabled for current weekday
        if let weekdayData = UserDefaults.standard.data(forKey: "selectedWeekdays"),
           let selectedWeekdays = try? JSONDecoder().decode([Int].self, from: weekdayData) {
            if !selectedWeekdays.contains(currentWeekday) {
                let weekdayName = calendar.weekdaySymbols[currentWeekday - 1]
                print("🗓️ Notifications disabled for \(weekdayName) - skipping")
                return false
            }
        } else {
            // Default to Monday-Friday if no settings found
            let defaultWeekdays = [2, 3, 4, 5, 6] // Monday-Friday
            if !defaultWeekdays.contains(currentWeekday) {
                let weekdayName = calendar.weekdaySymbols[currentWeekday - 1]
                print("🗓️ Notifications disabled for \(weekdayName) (default) - skipping")
                return false
            }
        }
        
        // Convert times to minutes since midnight for easier comparison
        let currentMinutesSinceMidnight = currentHour * 60 + currentMinute
        let startMinutesSinceMidnight = startHour * 60 + startMinute
        let endMinutesSinceMidnight = endHour * 60 + endMinute
        
        let isWithinActiveHours: Bool
        if startMinutesSinceMidnight <= endMinutesSinceMidnight {
            // Normal case: start time is before end time (e.g., 6:00 to 23:00)
            isWithinActiveHours = currentMinutesSinceMidnight >= startMinutesSinceMidnight && 
                                  currentMinutesSinceMidnight <= endMinutesSinceMidnight
        } else {
            // Overnight case: start time is after end time (e.g., 22:00 to 06:00)
            isWithinActiveHours = currentMinutesSinceMidnight >= startMinutesSinceMidnight || 
                                  currentMinutesSinceMidnight <= endMinutesSinceMidnight
        }
        
        if !isWithinActiveHours {
            print("🌙 Outside notification hours (\(String(format: "%02d:%02d", startHour, startMinute)) - \(String(format: "%02d:%02d", endHour, endMinute))) - skipping")
        }
        
        return isWithinActiveHours
    }
    
    private func sendNotification(for departure: Departure, line: TransitLine) async {
        let content = UNMutableNotificationContent()
        content.title = "KollektivWidget"
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
        // Use tripId to ensure each specific departure only notifies once, even if delayed
        "\(departure.tripId)-\(departure.line)-\(departure.destination)"
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
        cleanupOldNotifications()
        return Set(arr)
    }
    
    private func cleanupOldNotifications() {
        let cleanupInterval: TimeInterval = 24 * 60 * 60 // 24 hours
        let lastCleanup = UserDefaults.standard.double(forKey: "lastNotificationCleanup")
        let now = Date().timeIntervalSince1970
        
        if now - lastCleanup > cleanupInterval {
            // Clear all old notification records daily
            UserDefaults.standard.removeObject(forKey: "notifiedDepartures")
            UserDefaults.standard.set(now, forKey: "lastNotificationCleanup")
            print("🧹 Cleaned up old notification records")
        }
    }
}

// Shared structures
struct SavedStop: Codable, Identifiable {
    let id: String
    let name: String
}


