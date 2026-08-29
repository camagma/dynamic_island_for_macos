import AppKit
import Combine
import EventKit
import Foundation

struct CalendarItem: Identifiable {
    let id = UUID()
    let title: String
    let timeText: String
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var isExpanded = false
    @Published private(set) var timeText = ""
    @Published private(set) var dateText = ""
    @Published private(set) var musicText = "Музыка не играет"
    @Published private(set) var isMusicPlaying = false
    @Published private(set) var calendarItems: [CalendarItem] = []
    @Published private(set) var calendarStatusText = "Запрос доступа к календарю..."

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE, d MMM")
        return formatter
    }()

    private let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let eventStore = EKEventStore()
    private var cancellables = Set<AnyCancellable>()
    private var didRequestCalendarAccess = false

    func start() {
        refreshTime()
        refreshMusic()
        requestCalendarAccessIfNeeded()

        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshTime()
            }
            .store(in: &cancellables)

        Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshMusic()
            }
            .store(in: &cancellables)

        Timer.publish(every: 500, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshCalendar()
            }
            .store(in: &cancellables)
    }

    private func refreshTime() {
        let now = Date()
        timeText = timeFormatter.string(from: now)
        dateText = dateFormatter.string(from: now)
    }

    private func refreshMusic() {
        if isAppRunning(bundleIdentifier: "com.apple.Music"),
           let track = runAppleScript(Self.musicScript) {
            musicText = track
            isMusicPlaying = true
            return
        }

        if isAppRunning(bundleIdentifier: "com.spotify.client"),
           let track = runAppleScript(Self.spotifyScript) {
            musicText = track
            isMusicPlaying = true
            return
        }

        musicText = "nothing's playing"
        isMusicPlaying = false
    }

    private func requestCalendarAccessIfNeeded() {
        guard !didRequestCalendarAccess else {
            return
        }

        didRequestCalendarAccess = true

        Task {
            do {
                let granted: Bool

                if #available(macOS 14.0, *) {
                    granted = try await eventStore.requestFullAccessToEvents()
                } else {
                    granted = try await withCheckedThrowingContinuation { continuation in
                        eventStore.requestAccess(to: .event) { granted, error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume(returning: granted)
                            }
                        }
                    }
                }

                if granted {
                    refreshCalendar()
                } else {
                    calendarItems = []
                    calendarStatusText = "no access for calendar"
                }
            } catch {
                calendarItems = []
                calendarStatusText = "calendar is unreachable"
            }
        }
    }

    private func refreshCalendar() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            guard status == .fullAccess else {
                calendarItems = []
                calendarStatusText = "no access for calendar"
                return
            }
        } else {
            guard status == .authorized else {
                calendarItems = []
                calendarStatusText = "no access for calendar"
                return
            }
        }

        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(3)

        calendarItems = events.map { event in
            CalendarItem(
                title: event.title.isEmpty ? "no name" : event.title,
                timeText: eventTimeFormatter.string(from: event.startDate)
            )
        }

        calendarStatusText = calendarItems.isEmpty ? "no events for 7 days" : ""
    }

    private func isAppRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleIdentifier
        }
    }

    private func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        let output = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        let text = output?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return error == nil && !text.isEmpty ? text : nil
    }

    private static let musicScript = """
    tell application id "com.apple.Music"
        if player state is playing then
            set trackName to name of current track
            set artistName to artist of current track
            return artistName & " - " & trackName
        end if
    end tell
    return ""
    """

    private static let spotifyScript = """
    tell application id "com.spotify.client"
        if player state is playing then
            set trackName to name of current track
            set artistName to artist of current track
            return artistName & " - " & trackName
        end if
    end tell
    return ""
    """
}
