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
        // Request notification permissions
        requestNotificationPermission()
        
        // Set up status bar item
        setupStatusBar()
        
        // Start monitoring departures
        startMonitoring()
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else {
                print("Notification permission denied")
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
        popover.behavior = .transient
    }
    
    @objc private func togglePopover() {
        if let button = statusBarItem.button {
            if popover.isShown {
                popover.close()
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
        let stops = UserDefaults.standard.array(forKey: "savedStops") as? [String] ?? []
        let leadTime = UserDefaults.standard.integer(forKey: "leadTimeMinutes")
        
        // Use default lead time if not set
        let effectiveLeadTime = leadTime > 0 ? leadTime : 5
        
        for stopId in stops {
            await checkStop(stopId: stopId, leadTimeMinutes: effectiveLeadTime)
        }
    }
    
    private func checkStop(stopId: String, leadTimeMinutes: Int) async {
        do {
            let departures = try await EnturAPI.getDepartures(stopId: stopId)
            
            for departure in departures {
                if departure.shouldNotify(leadTimeMinutes: leadTimeMinutes) {
                    await sendNotification(for: departure)
                }
            }
        } catch {
            print("Error fetching departures for \(stopId): \(error)")
        }
    }
    
    private func sendNotification(for departure: Departure) async {
        let content = UNMutableNotificationContent()
        content.title = "\(departure.transportEmoji) Ruter Departure"
        content.body = "Line \(departure.line) to \(departure.destination) leaves in \(departure.minutesUntilDeparture()) minutes from \(departure.stopName)"
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
