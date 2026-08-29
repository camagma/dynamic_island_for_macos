import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private enum Layout {
        static let compactSize = CGSize(width: 178, height: 50)
        static let expandedSize = CGSize(width: 430, height: 154)
        static let compactTopInset: CGFloat = -18
        static let expandedTopInset: CGFloat = -5
        static let hoverWidth: CGFloat = 178
        static let hoverHeight: CGFloat = 0
    }

    private let model = IslandModel()
    private let window: NSPanel
    private var hoverTimer: Timer?
    private var expanded = false

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

        let view = IslandView(model: model)
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        window.contentView = hostingView

        positionWindow(expanded: false, animated: false)
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

    private func updateHoverState() {
        guard let screen = screenContainingMouse() ?? NSScreen.main else {
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let hoverRect = CGRect(
            x: screen.frame.midX - Layout.hoverWidth / 2,
            y: screen.frame.maxY - Layout.hoverHeight,
            width: Layout.hoverWidth,
            height: Layout.hoverHeight
        )

        let shouldExpand = hoverRect.contains(mouseLocation) || window.frame.insetBy(dx: -18, dy: -18).contains(mouseLocation)
        guard shouldExpand != expanded else {
            return
        }

        expanded = shouldExpand
        model.isExpanded = shouldExpand
        positionWindow(expanded: shouldExpand, animated: true)
    }

    private func positionWindow(expanded: Bool, animated: Bool) {
        guard let screen = NSScreen.main else {
            return
        }

        let size = expanded ? Layout.expandedSize : Layout.compactSize
        let topInset = expanded ? Layout.expandedTopInset : Layout.compactTopInset
        let frame = CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - topInset,
            width: size.width,
            height: size.height
        )

        window.setFrame(frame, display: true, animate: animated)
    }

    private func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) }
    }
}
