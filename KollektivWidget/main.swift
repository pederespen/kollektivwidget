import Cocoa
import SwiftUI

// Entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarItem: NSStatusItem!
    var popover: NSPopover!
    var contentView: ContentView?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Set up status bar item first
        setupStatusBar()
        
        logBundleInfo()
        
        // Trigger initial data load by briefly showing the popover to initialize the view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.triggerInitialDataLoad()
        }
    }
    
    private func triggerInitialDataLoad() {
        guard let button = statusBarItem.button else { return }
        // Briefly show and hide the popover to trigger onAppear
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.popover.close()
        }
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
        contentView = ContentView(updateStatusBar: { [weak self] title, symbol in
            print("📍 Status bar callback received: '\(title)' with symbol: \(symbol ?? "nil")")
            guard let button = self?.statusBarItem.button else { 
                print("❌ No status bar button available")
                return 
            }
            // Update icon
            if let symbolName = symbol {
                button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "KollektivWidget")
            }
            // Update title to include line + minutes
            button.title = " " + title
            print("✅ Status bar updated successfully")
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
    

    
    // Removed unused event monitor
    

    

    

    

    



}

// Shared structures
struct SavedStop: Codable, Identifiable {
    let id: String
    let name: String
}


