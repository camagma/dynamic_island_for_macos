import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let model = IslandModel()
    private let layoutCalculator = NotchLayoutCalculator()
    private let window: NSPanel
    private var hoverTimer: Timer?
    private var expanded = false
    private var forcedExpandedUntil: Date?
    private var cancellables = Set<AnyCancellable>()

    init() {
        window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.isMovable = false
        window.isOpaque = false
        window.level = .statusBar
        window.titleVisibility = .hidden

        model.updateNotchTextAvoidance(layoutCalculator.textAvoidance())

        let view = IslandView(model: model)
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        window.contentView = hostingView

        positionWindow(expanded: false, animated: false)

        model.expandRequests
            .sink { [weak self] in
                self?.forceExpand()
            }
            .store(in: &cancellables)
    }

    func show() {
        window.orderFrontRegardless()
        model.start()

        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateHoverState()
            }
        }
    }

    func addTestNotification() {
        model.addTestNotification()
    }

    func adjustNotchLayout(_ adjustment: NotchLayoutAdjustment) {
        layoutCalculator.apply(adjustment)
        model.updateNotchTextAvoidance(layoutCalculator.textAvoidance())
        positionWindow(expanded: expanded, animated: true)
    }

    func applyNotchPreset(_ preset: NotchLayoutPreset) {
        layoutCalculator.applyPreset(preset)
        model.updateNotchTextAvoidance(layoutCalculator.textAvoidance())
        positionWindow(expanded: expanded, animated: true)
    }

    private func updateHoverState() {
        guard let screen = screenContainingMouse() ?? NSScreen.main else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let hoverRect = layoutCalculator.hoverRect(on: screen)

        let isForcedExpanded = forcedExpandedUntil.map { Date() < $0 } ?? false
        let shouldExpand = isForcedExpanded || hoverRect.contains(mouseLocation) || window.frame.insetBy(dx: -18, dy: -18).contains(mouseLocation)
        guard shouldExpand != expanded else {
            return
        }

        if shouldExpand {
            model.refreshForOpening()
        }

        expanded = shouldExpand
        model.isExpanded = shouldExpand
        positionWindow(expanded: shouldExpand, animated: true)
        model.setPlaybackProgressActive(shouldExpand)
    }

    private func positionWindow(expanded: Bool, animated: Bool) {
        guard let screen = NSScreen.main else {
            return
        }

        let frame = expanded ? layoutCalculator.expandedFrame(on: screen) : layoutCalculator.compactFrame(on: screen)

        window.setFrame(frame, display: true, animate: animated)
    }

    private func forceExpand(duration: TimeInterval = 7) {
        forcedExpandedUntil = Date().addingTimeInterval(duration)

        guard !expanded else {
            return
        }

        model.refreshForOpening()
        expanded = true
        model.isExpanded = true
        positionWindow(expanded: true, animated: true)
        model.setPlaybackProgressActive(true)
    }

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }
}
