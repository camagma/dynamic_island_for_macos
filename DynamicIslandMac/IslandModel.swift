import AppKit
import Combine
import EventKit
import Foundation

struct CalendarItem: Identifiable {
    let id = UUID()
    let title: String
    let timeText: String
    let startDate: Date
    let eventIdentifier: String?
}

struct CalendarDay: Identifiable {
    let id = UUID()
    let dayNumber: Int?
    let isToday: Bool
    let hasEvents: Bool
}

struct IslandNotification: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let timeText: String
}

enum AudioControlAction {
    case previous
    case playPause
    case next
}

private struct AudioSource {
    let displayName: String
    let bundleIdentifier: String
    let snapshotScript: String
    let controlScripts: [AudioControlAction: String]
}

private struct AudioSnapshot {
    let title: String
    let elapsed: TimeInterval?
    let duration: TimeInterval?
    let isPlaying: Bool
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var isExpanded = false
    @Published private(set) var timeText = ""
    @Published private(set) var dateText = ""
    @Published private(set) var musicText = "Nothing is playing"
    @Published private(set) var audioSourceName = "No audio source"
    @Published private(set) var isAudioAvailable = false
    @Published private(set) var isMusicPlaying = false
    @Published private(set) var audioProgress: Double?
    @Published private(set) var audioElapsedText = "--:--"
    @Published private(set) var audioDurationText = "--:--"
    @Published private(set) var supportsAudioControls = false
    @Published private(set) var calendarItems: [CalendarItem] = []
    @Published private(set) var calendarDays: [CalendarDay] = []
    @Published private(set) var monthTitle = ""
    @Published private(set) var weekdaySymbols: [String] = []
    @Published private(set) var calendarStatusText = "Calendar access required"
    @Published private(set) var notifications: [IslandNotification] = []
    @Published private(set) var notificationStatusText = "No new notifications"
    @Published private(set) var gmailInboxMessages: [GmailNotification] = []
    @Published private(set) var gmailPageText = "Gmail"
    @Published private(set) var isGmailLoading = false
    @Published private(set) var canLoadPreviousGmailPage = false
    @Published private(set) var canLoadNextGmailPage = false
    @Published private(set) var clipboardText = "Clipboard is empty"
    @Published private(set) var hasClipboardText = false
    @Published private(set) var notchTextAvoidance = NotchTextAvoidance.fallback
    let expandRequests = PassthroughSubject<TimeInterval, Never>()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEE d")
        return formatter
    }()

    private let eventTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }()

    private let eventStore = EKEventStore()
    private let gmailService = GmailService()
    private var didRequestCalendarAccess = false
    private var currentAudioSource: AudioSource?
    private var audioElapsed: TimeInterval?
    private var audioDuration: TimeInterval?
    private var audioSnapshotDate: Date?
    private var playbackProgressTimer: Timer?
    private var gmailPollingTimer: Timer?
    private var lockedAudioSourceBundleIdentifier: String?
    private var lastSuccessfulAudioSourceBundleIdentifier: String?
    private let calendarCacheDuration: TimeInterval = 300
    private let gmailPollingInterval: TimeInterval = 30
    private var calendarCacheDate: Date?
    private var isGmailPolling = false
    private var gmailPageTokens: [String?] = [nil]
    private var gmailPageIndex = 0
    private var gmailNextPageToken: String?

    func start() {
        refreshCalendarShell()
        startGmailPollingIfConfigured()
    }

    func refreshForOpening() {
        refreshTime()
        refreshMusic()
        refreshClipboard()
        refreshCalendarForOpening()
    }

    func openCalendar(for item: CalendarItem? = nil) {
        let appURL = URL(fileURLWithPath: "/System/Applications/Calendar.app")
        let configuration = NSWorkspace.OpenConfiguration()

        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
    }

    func addNotification(title: String, body: String) {
        let notification = IslandNotification(
            title: title,
            body: body,
            timeText: eventTimeFormatter.string(from: Date())
        )

        notifications.insert(notification, at: 0)
        notifications = Array(notifications.prefix(5))
        notificationStatusText = ""
        expandRequests.send(5)
    }

    func addTestNotification() {
        addNotification(title: "Test notification", body: "The island expands automatically.")
    }

    func updateNotchTextAvoidance(_ avoidance: NotchTextAvoidance) {
        notchTextAvoidance = avoidance
    }

    func controlAudio(_ action: AudioControlAction) {
        let source = currentAudioSource ?? Self.audioSources.first {
            !$0.controlScripts.isEmpty && isAppRunning(bundleIdentifier: $0.bundleIdentifier)
        }

        guard let source,
              let script = source.controlScripts[action] else {
            return
        }

        currentAudioSource = source
        lockedAudioSourceBundleIdentifier = source.bundleIdentifier
        runAppleScriptIgnoringOutput(script)
        refreshLockedAudioSource(source)

        if isExpanded {
            setPlaybackProgressActive(true)
        }
    }

    func setPlaybackProgressActive(_ isActive: Bool) {
        playbackProgressTimer?.invalidate()
        playbackProgressTimer = nil

        guard isActive,
              isMusicPlaying,
              audioElapsed != nil,
              audioDuration != nil else {
            return
        }

        playbackProgressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advancePlaybackProgress()
            }
        }
    }

    func checkGmailNow() {
        Task {
            let didShowNewMessages = await pollGmail(showStatus: false)
            gmailPageTokens = [nil]
            gmailPageIndex = 0
            gmailNextPageToken = nil
            await loadGmailInboxPage(pageIndex: 0, pageToken: nil, showStatus: false)

            if !didShowNewMessages {
                await loadRecentGmailMessagesForDisplay(showStatus: true)
            }
        }
    }

    func reloadGmailInbox() {
        Task {
            gmailPageTokens = [nil]
            gmailPageIndex = 0
            gmailNextPageToken = nil
            await loadGmailInboxPage(pageIndex: 0, pageToken: nil, showStatus: true)
        }
    }

    func loadPreviousGmailPage() {
        guard gmailPageIndex > 0 else {
            return
        }

        Task {
            let previousIndex = gmailPageIndex - 1
            await loadGmailInboxPage(pageIndex: previousIndex, pageToken: gmailPageTokens[previousIndex], showStatus: true)
        }
    }

    func loadNextGmailPage() {
        guard let gmailNextPageToken else {
            return
        }

        Task {
            let nextIndex = gmailPageIndex + 1
            if gmailPageTokens.count <= nextIndex {
                gmailPageTokens.append(gmailNextPageToken)
            }
            await loadGmailInboxPage(pageIndex: nextIndex, pageToken: gmailNextPageToken, showStatus: true, appending: true)
        }
    }

    private func refreshTime() {
        let now = Date()
        timeText = timeFormatter.string(from: now)
        dateText = dateFormatter.string(from: now)
    }

    private func startGmailPollingIfConfigured() {
        gmailPollingTimer?.invalidate()
        gmailPollingTimer = nil

        guard gmailService.isConfigured else {
            return
        }

        Task {
            let didShowNewMessages = await pollGmail(showStatus: false)
            if !didShowNewMessages {
                await loadRecentGmailMessagesForDisplay(showStatus: false)
            }
            await loadGmailInboxPage(pageIndex: 0, pageToken: nil, showStatus: false)
        }

        gmailPollingTimer = Timer.scheduledTimer(withTimeInterval: gmailPollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollGmail(showStatus: false)
            }
        }
    }

    @discardableResult
    private func pollGmail(showStatus: Bool) async -> Bool {
        guard gmailService.isConfigured else {
            if showStatus {
                notificationStatusText = "Gmail is not configured"
                expandRequests.send(5)
            }
            return false
        }
        guard !isGmailPolling else {
            return false
        }

        isGmailPolling = true
        defer {
            isGmailPolling = false
        }

        do {
            let messages = try await gmailService.pollNewInboxMessages()
            if messages.isEmpty && showStatus {
                notificationStatusText = "No new Gmail messages"
                expandRequests.send(5)
            }

            for message in messages.reversed() {
                insertGmailInboxMessage(message)
                addNotification(
                    title: message.subject,
                    body: gmailBodyText(from: message)
                )
            }

            return !messages.isEmpty
        } catch {
            notificationStatusText = "Gmail API unavailable"
            if showStatus {
                expandRequests.send(5)
            }
            return false
        }
    }

    private func loadRecentGmailMessagesForDisplay(showStatus: Bool) async {
        guard gmailService.isConfigured else {
            if showStatus {
                notificationStatusText = "Gmail is not configured"
                expandRequests.send(5)
            }
            return
        }

        do {
            let messages = try await gmailService.recentUnreadMessages(limit: 3)
            guard !messages.isEmpty else {
                if showStatus {
                    notificationStatusText = "No unread Gmail messages"
                    expandRequests.send(5)
                }
                return
            }

            notifications.removeAll()
            gmailInboxMessages.removeAll()
            for message in messages.reversed() {
                insertGmailInboxMessage(message)
                insertNotificationWithoutExpanding(
                    title: message.subject,
                    body: gmailBodyText(from: message)
                )
            }

            notificationStatusText = ""
            if showStatus {
                expandRequests.send(5)
            }
        } catch {
            notificationStatusText = "Gmail API unavailable"
            if showStatus {
                expandRequests.send(5)
            }
        }
    }

    private func loadGmailInboxPage(pageIndex: Int, pageToken: String?, showStatus: Bool, appending: Bool = false) async {
        guard gmailService.isConfigured else {
            gmailInboxMessages = []
            gmailPageText = "Gmail not configured"
            canLoadPreviousGmailPage = false
            canLoadNextGmailPage = false
            if showStatus {
                notificationStatusText = "Gmail is not configured"
                expandRequests.send(5)
            }
            return
        }

        isGmailLoading = true
        defer {
            isGmailLoading = false
        }

        do {
            let page = try await gmailService.inboxPage(pageToken: pageToken, pageSize: 5)
            if appending {
                appendGmailInboxMessages(page.messages)
            } else {
                gmailInboxMessages = page.messages
            }
            gmailPageIndex = pageIndex
            gmailNextPageToken = page.nextPageToken
            gmailPageText = gmailInboxMessages.isEmpty ? "Gmail" : "\(gmailInboxMessages.count) emails"
            canLoadPreviousGmailPage = pageIndex > 0
            canLoadNextGmailPage = page.nextPageToken != nil

            if page.messages.isEmpty {
                notificationStatusText = "No Gmail inbox messages"
            }

            if showStatus {
                expandRequests.send(5)
            }
        } catch {
            gmailInboxMessages = []
            gmailPageText = "Gmail unavailable"
            canLoadPreviousGmailPage = pageIndex > 0
            canLoadNextGmailPage = false
            notificationStatusText = "Gmail API unavailable"
            if showStatus {
                expandRequests.send(5)
            }
        }
    }

    private func appendGmailInboxMessages(_ messages: [GmailNotification]) {
        var existingIDs = Set(gmailInboxMessages.map(\.id))

        for message in messages where !existingIDs.contains(message.id) {
            gmailInboxMessages.append(message)
            existingIDs.insert(message.id)
        }
    }

    private func insertGmailInboxMessage(_ message: GmailNotification) {
        gmailInboxMessages.removeAll { $0.id == message.id }
        gmailInboxMessages.insert(message, at: 0)
        gmailInboxMessages = Array(gmailInboxMessages.prefix(30))
        gmailPageText = "\(gmailInboxMessages.count) emails"
    }

    private func gmailBodyText(from message: GmailNotification) -> String {
        let sender = message.senderDisplayName
        guard !message.snippet.isEmpty else {
            return sender
        }

        return "\(sender): \(message.snippet)"
    }

    private func insertNotificationWithoutExpanding(title: String, body: String) {
        let notification = IslandNotification(
            title: title,
            body: body,
            timeText: eventTimeFormatter.string(from: Date())
        )

        notifications.insert(notification, at: 0)
        notifications = Array(notifications.prefix(5))
    }

    private func refreshMusic() {
        if let lockedAudioSourceBundleIdentifier,
           let lockedSource = Self.audioSources.first(where: { $0.bundleIdentifier == lockedAudioSourceBundleIdentifier }),
           isAppRunning(bundleIdentifier: lockedSource.bundleIdentifier) {
            if refreshLockedAudioSource(lockedSource) {
                return
            }

            self.lockedAudioSourceBundleIdentifier = nil
        }

        var pausedFallback: (source: AudioSource, snapshot: AudioSnapshot)?

        for source in prioritizedAudioSources() where isAppRunning(bundleIdentifier: source.bundleIdentifier) {
            if let output = runAppleScript(source.snapshotScript),
               let snapshot = parseAudioSnapshot(output) {
                if snapshot.isPlaying {
                    applyAudioSnapshot(snapshot, source: source)
                    return
                }

                if pausedFallback == nil {
                    pausedFallback = (source, snapshot)
                }
            }
        }

        if let pausedFallback {
            applyAudioSnapshot(pausedFallback.snapshot, source: pausedFallback.source)
            return
        }

        musicText = "Nothing is playing"
        audioSourceName = "No audio source"
        isAudioAvailable = false
        isMusicPlaying = false
        audioElapsed = nil
        audioDuration = nil
        audioSnapshotDate = nil
        audioProgress = nil
        audioElapsedText = "--:--"
        audioDurationText = "--:--"
        supportsAudioControls = false
        currentAudioSource = nil
        lockedAudioSourceBundleIdentifier = nil
        setPlaybackProgressActive(false)
    }

    private func prioritizedAudioSources() -> [AudioSource] {
        guard let lastSuccessfulAudioSourceBundleIdentifier,
              let index = Self.audioSources.firstIndex(where: { $0.bundleIdentifier == lastSuccessfulAudioSourceBundleIdentifier }) else {
            return Self.audioSources
        }

        var sources = Self.audioSources
        let lastSource = sources.remove(at: index)
        sources.insert(lastSource, at: 0)
        return sources
    }

    @discardableResult
    private func refreshLockedAudioSource(_ source: AudioSource) -> Bool {
        guard let output = runAppleScript(source.snapshotScript),
              let snapshot = parseAudioSnapshot(output) else {
            return false
        }

        applyAudioSnapshot(snapshot, source: source)
        return true
    }

    private func applyAudioSnapshot(_ snapshot: AudioSnapshot, source: AudioSource) {
        musicText = snapshot.title
        audioSourceName = source.displayName
        isAudioAvailable = true
        isMusicPlaying = snapshot.isPlaying
        audioElapsed = snapshot.elapsed
        audioDuration = snapshot.duration
        audioSnapshotDate = Date()
        updatePlaybackDisplay(elapsed: snapshot.elapsed, duration: snapshot.duration)
        supportsAudioControls = !source.controlScripts.isEmpty
        currentAudioSource = source
        lastSuccessfulAudioSourceBundleIdentifier = source.bundleIdentifier
    }

    private func refreshCalendarForOpening() {
        let status = EKEventStore.authorizationStatus(for: .event)

        if status == .notDetermined {
            requestCalendarAccessIfNeeded()
        } else if isCalendarCacheValid {
            return
        } else {
            refreshCalendar()
        }
    }

    private var isCalendarCacheValid: Bool {
        guard let calendarCacheDate else {
            return false
        }

        return Date().timeIntervalSince(calendarCacheDate) < calendarCacheDuration
            && Calendar.current.isDate(calendarCacheDate, inSameDayAs: Date())
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
                    calendarCacheDate = nil
                    calendarStatusText = "No calendar access"
                }
            } catch {
                calendarItems = []
                calendarCacheDate = nil
                calendarStatusText = "Calendar is unavailable"
            }
        }
    }

    private func refreshCalendar() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) {
            guard status == .fullAccess else {
                calendarItems = []
                calendarCacheDate = nil
                refreshCalendarShell(events: [])
                calendarStatusText = "No calendar access"
                return
            }
        } else {
            guard status == .authorized else {
                calendarItems = []
                calendarCacheDate = nil
                refreshCalendarShell(events: [])
                calendarStatusText = "No calendar access"
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
                title: event.title.isEmpty ? "Untitled" : event.title,
                timeText: eventTimeFormatter.string(from: event.startDate),
                startDate: event.startDate,
                eventIdentifier: event.eventIdentifier
            )
        }

        calendarStatusText = calendarItems.isEmpty ? "No events for 7 days" : ""
        refreshCalendarShell(events: eventStore.events(matching: monthPredicate()))
        calendarCacheDate = Date()
    }

    private func refreshCalendarShell(events: [EKEvent] = []) {
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
        let numberOfDays = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let emptyPrefixCount = (firstWeekday - calendar.firstWeekday + 7) % 7
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)

        let eventDays = Set(events.map {
            calendar.component(.day, from: $0.startDate)
        })

        let prefix = (0..<emptyPrefixCount).map { _ in
            CalendarDay(dayNumber: nil, isToday: false, hasEvents: false)
        }
        let days = (1...numberOfDays).map { day in
            let isToday = todayComponents.day == day
            return CalendarDay(dayNumber: day, isToday: isToday, hasEvents: eventDays.contains(day))
        }

        calendarDays = prefix + days
        monthTitle = monthFormatter.string(from: monthStart).capitalized
        weekdaySymbols = orderedWeekdaySymbols()
    }

    private func monthPredicate() -> NSPredicate {
        let calendar = Calendar.current
        let now = Date()
        let interval = calendar.dateInterval(of: .month, for: now)
        let start = interval?.start ?? now
        let end = interval?.end ?? now
        return eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
    }

    private func orderedWeekdaySymbols() -> [String] {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        let firstIndex = Calendar.current.firstWeekday - 1
        return Array(symbols[firstIndex...] + symbols[..<firstIndex]).map {
            String($0.prefix(2)).uppercased()
        }
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

    private func runAppleScriptIgnoringOutput(_ source: String) {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
    }

    private func parseAudioSnapshot(_ output: String) -> AudioSnapshot? {
        let lines = output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard let title = lines.first,
              !title.isEmpty else {
            return nil
        }

        let elapsed = lines.indices.contains(1) ? parsePlaybackSeconds(lines[1]) : nil
        let duration = lines.indices.contains(2) ? parsePlaybackSeconds(lines[2]) : nil
        let state = lines.indices.contains(3) ? lines[3].lowercased() : "playing"

        return AudioSnapshot(
            title: title,
            elapsed: elapsed,
            duration: duration,
            isPlaying: state == "playing"
        )
    }

    private func parsePlaybackSeconds(_ text: String) -> TimeInterval? {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        let allowedCharacters = CharacterSet(charactersIn: "0123456789.+-eE")
        let cleaned = String(normalized.unicodeScalars.filter {
            allowedCharacters.contains($0)
        })

        guard let value = Double(cleaned),
              value.isFinite,
              value >= 0 else {
            return nil
        }

        return value
    }

    private func advancePlaybackProgress() {
        guard isMusicPlaying,
              let audioElapsed,
              let audioDuration,
              let audioSnapshotDate else {
            setPlaybackProgressActive(false)
            return
        }

        let elapsed = min(audioElapsed + Date().timeIntervalSince(audioSnapshotDate), audioDuration)
        updatePlaybackDisplay(elapsed: elapsed, duration: audioDuration)
    }

    private func updatePlaybackDisplay(elapsed: TimeInterval?, duration: TimeInterval?) {
        audioProgress = progress(elapsed: elapsed, duration: duration)
        audioElapsedText = formatPlaybackTime(elapsed)
        audioDurationText = formatPlaybackTime(duration)
    }

    private func progress(elapsed: TimeInterval?, duration: TimeInterval?) -> Double? {
        guard let elapsed,
              let duration,
              duration > 0 else {
            return nil
        }

        return min(max(elapsed / duration, 0), 1)
    }

    private func formatPlaybackTime(_ seconds: TimeInterval?) -> String {
        guard let seconds,
              seconds.isFinite,
              seconds >= 0 else {
            return "--:--"
        }

        let totalSeconds = Int(seconds.rounded())
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    private func refreshClipboard() {
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalized.isEmpty else {
            clipboardText = "Clipboard is empty"
            hasClipboardText = false
            return
        }

        clipboardText = String(normalized.prefix(90))
        hasClipboardText = true
    }

    private static let audioSources: [AudioSource] = [
        AudioSource(displayName: "Apple Music", bundleIdentifier: "com.apple.Music", snapshotScript: musicScript, controlScripts: musicControlScripts),
        AudioSource(displayName: "Spotify", bundleIdentifier: "com.spotify.client", snapshotScript: spotifyScript, controlScripts: spotifyControlScripts),
        AudioSource(displayName: "Podcasts", bundleIdentifier: "com.apple.podcasts", snapshotScript: podcastsScript, controlScripts: [:]),
        AudioSource(displayName: "VLC", bundleIdentifier: "org.videolan.vlc", snapshotScript: vlcScript, controlScripts: [:]),
        AudioSource(displayName: "QuickTime Player", bundleIdentifier: "com.apple.QuickTimePlayerX", snapshotScript: quickTimeScript, controlScripts: [:]),
        AudioSource(displayName: "Safari", bundleIdentifier: "com.apple.Safari", snapshotScript: safariScript, controlScripts: [:]),
        AudioSource(displayName: "Chrome", bundleIdentifier: "com.google.Chrome", snapshotScript: chromeScript, controlScripts: [:]),
        AudioSource(displayName: "Arc", bundleIdentifier: "company.thebrowser.Browser", snapshotScript: arcScript, controlScripts: [:])
    ]

    private static let musicScript = """
    tell application id "com.apple.Music"
        set playbackState to player state as text
        if playbackState is not "stopped" then
            try
                set trackName to name of current track
            on error
                return ""
            end try

            try
                set artistName to artist of current track
            on error
                set artistName to ""
            end try

            set displayTitle to trackName
            if artistName is not "" then
                set displayTitle to trackName & " - " & artistName
            end if

            set elapsedSeconds to ""
            set durationSeconds to ""

            try
                set elapsedSeconds to (round (player position)) as text
            end try

            try
                set durationSeconds to (round (duration of current track)) as text
            end try

            return displayTitle & linefeed & elapsedSeconds & linefeed & durationSeconds & linefeed & playbackState
        end if
    end tell
    return ""
    """

    private static let spotifyScript = """
    tell application id "com.spotify.client"
        set playbackState to player state as text
        if playbackState is not "stopped" then
            try
                set trackName to name of current track
            on error
                return ""
            end try

            try
                set artistName to artist of current track
            on error
                set artistName to ""
            end try

            set displayTitle to trackName
            if artistName is not "" then
                set displayTitle to trackName & " - " & artistName
            end if

            set elapsedSeconds to ""
            set durationSeconds to ""

            try
                set elapsedSeconds to (round (player position)) as text
            end try

            try
                set durationSeconds to (round ((duration of current track) / 1000)) as text
            end try

            return displayTitle & linefeed & elapsedSeconds & linefeed & durationSeconds & linefeed & playbackState
        end if
    end tell
    return ""
    """

    private static let musicControlScripts: [AudioControlAction: String] = [
        .previous: """
        tell application id "com.apple.Music" to previous track
        """,
        .playPause: """
        tell application id "com.apple.Music" to playpause
        """,
        .next: """
        tell application id "com.apple.Music" to next track
        """
    ]

    private static let spotifyControlScripts: [AudioControlAction: String] = [
        .previous: """
        tell application id "com.spotify.client" to previous track
        """,
        .playPause: """
        tell application id "com.spotify.client" to playpause
        """,
        .next: """
        tell application id "com.spotify.client" to next track
        """
    ]

    private static let podcastsScript = """
    tell application id "com.apple.podcasts"
        if player state is playing then
            set episodeName to name of current track
            return episodeName
        end if
    end tell
    return ""
    """

    private static let vlcScript = """
    tell application id "org.videolan.vlc"
        if playing then
            return name of current item
        end if
    end tell
    return ""
    """

    private static let quickTimeScript = """
    tell application id "com.apple.QuickTimePlayerX"
        if (count of documents) > 0 then
            if playing of front document then
                return name of front document
            end if
        end if
    end tell
    return ""
    """

    private static let safariScript = """
    tell application id "com.apple.Safari"
        if (count of windows) > 0 and (count of tabs of front window) > 0 then
            set pageTitle to name of current tab of front window
            if pageTitle contains "YouTube" or pageTitle contains "SoundCloud" or pageTitle contains "Twitch" then
                return pageTitle
            end if
        end if
    end tell
    return ""
    """

    private static let chromeScript = """
    tell application id "com.google.Chrome"
        if (count of windows) > 0 and (count of tabs of front window) > 0 then
            set pageTitle to title of active tab of front window
            if pageTitle contains "YouTube" or pageTitle contains "SoundCloud" or pageTitle contains "Twitch" then
                return pageTitle
            end if
        end if
    end tell
    return ""
    """

    private static let arcScript = """
    tell application id "company.thebrowser.Browser"
        if (count of windows) > 0 and (count of tabs of front window) > 0 then
            set pageTitle to title of active tab of front window
            if pageTitle contains "YouTube" or pageTitle contains "SoundCloud" or pageTitle contains "Twitch" then
                return pageTitle
            end if
        end if
    end tell
    return ""
    """
}
