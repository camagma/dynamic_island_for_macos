import AppKit
import SwiftUI

@main
struct DynamicIslandMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayController: OverlayWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let controller = OverlayWindowController()
        controller.show()
        overlayController = controller

        configureStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "DynamicIslandMac")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit DynamicIslandMac", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
