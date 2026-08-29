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
        menu.addItem(NSMenuItem(title: "Test Notification", action: #selector(testNotification), keyEquivalent: "n"))
        menu.addItem(calibrationMenuItem())
        menu.addItem(presetsMenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit DynamicIslandMac", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    private func calibrationMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Calibrate Notch", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        submenu.addItem(NSMenuItem(title: "Wider", action: #selector(makeWider), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Narrower", action: #selector(makeNarrower), keyEquivalent: ""))
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(NSMenuItem(title: "Taller", action: #selector(makeTaller), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Shorter", action: #selector(makeShorter), keyEquivalent: ""))
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(NSMenuItem(title: "Move Up", action: #selector(moveUp), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "Move Down", action: #selector(moveDown), keyEquivalent: ""))
        submenu.addItem(NSMenuItem.separator())
        submenu.addItem(NSMenuItem(title: "Reset", action: #selector(resetNotchLayout), keyEquivalent: ""))

        item.submenu = submenu
        return item
    }

    private func presetsMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Notch Presets", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        submenu.addItem(NSMenuItem(title: "MacBook Air 13-inch", action: #selector(applyMacBookAir13Preset), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "MacBook Air 15-inch", action: #selector(applyMacBookAir15Preset), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "MacBook Pro 14-inch", action: #selector(applyMacBookPro14Preset), keyEquivalent: ""))
        submenu.addItem(NSMenuItem(title: "MacBook Pro 16-inch", action: #selector(applyMacBookPro16Preset), keyEquivalent: ""))

        item.submenu = submenu
        return item
    }

    @objc private func testNotification() {
        overlayController?.addTestNotification()
    }

    @objc private func makeWider() {
        overlayController?.adjustNotchLayout(.wider)
    }

    @objc private func makeNarrower() {
        overlayController?.adjustNotchLayout(.narrower)
    }

    @objc private func makeTaller() {
        overlayController?.adjustNotchLayout(.taller)
    }

    @objc private func makeShorter() {
        overlayController?.adjustNotchLayout(.shorter)
    }

    @objc private func moveUp() {
        overlayController?.adjustNotchLayout(.moveUp)
    }

    @objc private func moveDown() {
        overlayController?.adjustNotchLayout(.moveDown)
    }

    @objc private func resetNotchLayout() {
        overlayController?.adjustNotchLayout(.reset)
    }

    @objc private func applyMacBookAir13Preset() {
        overlayController?.applyNotchPreset(.macBookAir13)
    }

    @objc private func applyMacBookAir15Preset() {
        overlayController?.applyNotchPreset(.macBookAir15)
    }

    @objc private func applyMacBookPro14Preset() {
        overlayController?.applyNotchPreset(.macBookPro14)
    }

    @objc private func applyMacBookPro16Preset() {
        overlayController?.applyNotchPreset(.macBookPro16)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
