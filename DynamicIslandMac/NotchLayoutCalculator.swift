import AppKit
import Foundation

struct NotchLayoutSettings {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var verticalOffset: CGFloat
    var hoverWidth: CGFloat
    var hoverHeight: CGFloat

    static let defaults = NotchLayoutSettings(
        notchWidth: 178,
        notchHeight: 0,
        verticalOffset: -18,
        hoverWidth: 190,
        hoverHeight: 42
    )
}

struct NotchTextAvoidance {
    let width: CGFloat
    let height: CGFloat

    static let fallback = NotchTextAvoidance(width: 200, height: 46)
}

enum NotchLayoutPreset: CaseIterable {
    case macBookAir13
    case macBookAir15
    case macBookPro14
    case macBookPro16

    var title: String {
        switch self {
        case .macBookAir13:
            return "MacBook Air 13-inch"
        case .macBookAir15:
            return "MacBook Air 15-inch"
        case .macBookPro14:
            return "MacBook Pro 14-inch"
        case .macBookPro16:
            return "MacBook Pro 16-inch"
        }
    }

    var settings: NotchLayoutSettings {
        switch self {
        case .macBookAir13:
            return NotchLayoutSettings(notchWidth: 178, notchHeight: 24, verticalOffset: -18, hoverWidth: 190, hoverHeight: 42)
        case .macBookAir15:
            return NotchLayoutSettings(notchWidth: 188, notchHeight: 24, verticalOffset: -18, hoverWidth: 202, hoverHeight: 42)
        case .macBookPro14:
            return NotchLayoutSettings(notchWidth: 196, notchHeight: 26, verticalOffset: -18, hoverWidth: 210, hoverHeight: 45)
        case .macBookPro16:
            return NotchLayoutSettings(notchWidth: 208, notchHeight: 26, verticalOffset: -18, hoverWidth: 224, hoverHeight: 45)
        }
    }
}

enum NotchLayoutAdjustment {
    case wider
    case narrower
    case taller
    case shorter
    case moveUp
    case moveDown
    case reset
}

struct NotchLayoutCalculator {
    private enum Keys {
        static let notchWidth = "NotchLayout.notchWidth"
        static let notchHeight = "NotchLayout.notchHeight"
        static let verticalOffset = "NotchLayout.verticalOffset"
        static let hoverWidth = "NotchLayout.hoverWidth"
        static let hoverHeight = "NotchLayout.hoverHeight"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        registerDefaults()
    }

    var settings: NotchLayoutSettings {
        NotchLayoutSettings(
            notchWidth: defaults.double(forKey: Keys.notchWidth),
            notchHeight: defaults.double(forKey: Keys.notchHeight),
            verticalOffset: defaults.double(forKey: Keys.verticalOffset),
            hoverWidth: defaults.double(forKey: Keys.hoverWidth),
            hoverHeight: defaults.double(forKey: Keys.hoverHeight)
        )
    }

    func compactFrame(on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let currentSettings = settings
        let size = CGSize(
            width: clamped(currentSettings.notchWidth, min: 96, max: min(260, screenFrame.width * 0.30)),
            height: clamped(currentSettings.notchHeight, min: 24, max: 56)
        )

        return centeredTopFrame(
            screenFrame: screenFrame,
            size: size,
            verticalOffset: currentSettings.verticalOffset
        )
    }

    func expandedFrame(on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let currentSettings = settings
        let baseWidth = clamped(screenFrame.width * 0.31, min: 430, max: 520)
        let expandedWidth = clamped(max(baseWidth, currentSettings.notchWidth * 2.35), min: 420, max: min(540, screenFrame.width - 80))
        let expandedHeight = clamped(expandedWidth * 0.58, min: 248, max: 306)

        return centeredTopFrame(
            screenFrame: screenFrame,
            size: CGSize(width: expandedWidth, height: expandedHeight),
            verticalOffset: currentSettings.verticalOffset + 13
        )
    }

    func textAvoidance() -> NotchTextAvoidance {
        let currentSettings = settings
        let effectiveNotchHeight = max(currentSettings.notchHeight, 34)

        return NotchTextAvoidance(
            width: clamped(currentSettings.notchWidth + 24, min: 140, max: 284),
            height: clamped(effectiveNotchHeight + 12, min: 42, max: 78)
        )
    }

    func hoverRect(on screen: NSScreen) -> CGRect {
        let screenFrame = screen.frame
        let currentSettings = settings
        let width = clamped(max(currentSettings.hoverWidth, currentSettings.notchWidth + 24), min: 120, max: min(420, screenFrame.width * 0.50))
        let height = clamped(currentSettings.hoverHeight, min: 24, max: 120)

        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    func apply(_ adjustment: NotchLayoutAdjustment) {
        var updated = settings

        switch adjustment {
        case .wider:
            updated.notchWidth += 8
            updated.hoverWidth += 8
        case .narrower:
            updated.notchWidth -= 8
            updated.hoverWidth -= 8
        case .taller:
            updated.notchHeight += 3
            updated.hoverHeight += 3
        case .shorter:
            updated.notchHeight -= 3
            updated.hoverHeight -= 3
        case .moveUp:
            updated.verticalOffset -= 2
        case .moveDown:
            updated.verticalOffset += 2
        case .reset:
            updated = .defaults
        }

        save(updated)
    }

    func applyPreset(_ preset: NotchLayoutPreset) {
        save(preset.settings)
    }

    private func registerDefaults() {
        let values = NotchLayoutSettings.defaults
        defaults.register(defaults: [
            Keys.notchWidth: values.notchWidth,
            Keys.notchHeight: values.notchHeight,
            Keys.verticalOffset: values.verticalOffset,
            Keys.hoverWidth: values.hoverWidth,
            Keys.hoverHeight: values.hoverHeight
        ])
    }

    private func save(_ settings: NotchLayoutSettings) {
        defaults.set(clamped(settings.notchWidth, min: 96, max: 260), forKey: Keys.notchWidth)
        defaults.set(clamped(settings.notchHeight, min: 24, max: 56), forKey: Keys.notchHeight)
        defaults.set(clamped(settings.verticalOffset, min: -34, max: 18), forKey: Keys.verticalOffset)
        defaults.set(clamped(settings.hoverWidth, min: 120, max: 420), forKey: Keys.hoverWidth)
        defaults.set(clamped(settings.hoverHeight, min: 24, max: 120), forKey: Keys.hoverHeight)
    }

    private func centeredTopFrame(screenFrame: CGRect, size: CGSize, verticalOffset: CGFloat) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height - verticalOffset,
            width: size.width,
            height: size.height
        )
    }

    private func clamped(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
