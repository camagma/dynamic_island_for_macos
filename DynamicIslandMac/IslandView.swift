import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandModel
    private let calendarColumns = Array(repeating: GridItem(.fixed(21), spacing: 2), count: 7)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: model.isExpanded ? 18 : 14, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: model.isExpanded ? 18 : 14, style: .continuous)
                        .stroke(Color.white.opacity(model.isExpanded ? 0.10 : 0.06), lineWidth: 1)
                )

            if model.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                compactContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.snappy(duration: 0.18), value: model.isExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactContent: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(model.isMusicPlaying ? Color.green : Color.white.opacity(0.32))
                .frame(width: 6, height: 6)

            if !model.notifications.isEmpty {
                Image(systemName: "bell.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(.horizontal, 14)
    }

    private var expandedContent: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 16
            let contentWidth = max(0, proxy.size.width - horizontalPadding * 2)

            VStack(alignment: .leading, spacing: 10) {
                notchSafeTopRow(contentWidth: contentWidth)

                Divider()
                    .overlay(Color.white.opacity(0.14))

                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        nowPlayingPanel
                        upcomingEvents
                        notificationCentre
                        Spacer(minLength: 0)
                        clipboardPreview
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    monthCalendarGrid
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 11)
            .padding(.bottom, 13)
        }
    }

    private func notchSafeTopRow(contentWidth: CGFloat) -> some View {
        let gapWidth = min(model.notchTextAvoidance.width, max(120, contentWidth - 250))
        let sideWidth = max(112, (contentWidth - gapWidth) / 2)
        let topHeight = model.notchTextAvoidance.height

        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.timeText)
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)

                musicRow
            }
            .frame(width: sideWidth, alignment: .topLeading)

            Spacer(minLength: 0)
                .frame(width: gapWidth)

            VStack(alignment: .trailing, spacing: 6) {
                Text(model.monthTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(model.dateText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(width: sideWidth, alignment: .topTrailing)
        }
        .frame(height: topHeight, alignment: .top)
    }

    private var musicRow: some View {
        HStack(spacing: 10) {
            Image(systemName: model.isAudioAvailable ? "music.note" : "speaker.slash.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.isMusicPlaying ? Color.green : Color.white.opacity(0.48))
                .frame(width: 17)

            Text(model.musicText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(model.isMusicPlaying ? 0.92 : 0.62))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var nowPlayingPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                audioSourceBadge

                Spacer(minLength: 8)

                transportControls
            }

            HStack(spacing: 7) {
                Text(model.audioElapsedText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: 30, alignment: .leading)

                progressBar

                Text(model.audioDurationText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: 30, alignment: .trailing)
            }
        }
    }

    private var audioSourceBadge: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(model.isMusicPlaying ? Color.green.opacity(0.20) : Color.white.opacity(0.07))
                    .frame(width: 17, height: 17)

                Image(systemName: model.isMusicPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(model.isMusicPlaying ? Color.green : Color.white.opacity(0.46))
            }

            Text(model.audioSourceName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(model.isAudioAvailable ? 0.72 : 0.46))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private var transportControls: some View {
        HStack(spacing: 5) {
            audioControlButton(systemName: "backward.fill", action: .previous)
            audioControlButton(systemName: model.isMusicPlaying ? "pause.fill" : "play.fill", action: .playPause)
            audioControlButton(systemName: "forward.fill", action: .next)
        }
    }

    private func audioControlButton(systemName: String, action: AudioControlAction) -> some View {
        Button {
            model.controlAudio(action)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(model.supportsAudioControls ? 0.78 : 0.28))
                .frame(width: 20, height: 20)
                .background(
                    Circle()
                        .fill(Color.white.opacity(model.supportsAudioControls ? 0.08 : 0.035))
                )
        }
        .buttonStyle(.plain)
        .disabled(!model.supportsAudioControls)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let progress = model.audioProgress ?? 0

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.10))

                Capsule(style: .continuous)
                    .fill(model.isMusicPlaying ? Color.green : Color.white.opacity(0.38))
                    .frame(width: proxy.size.width * progress)
            }
        }
        .frame(height: 4)
        .opacity(model.audioProgress == nil ? 0.35 : 1)
    }

    private var monthCalendarGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: 13)

                Text("Month")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.80))
            }

            LazyVGrid(columns: calendarColumns, spacing: 3) {
                ForEach(model.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white.opacity(0.38))
                        .frame(width: 21, height: 12)
                }

                ForEach(model.calendarDays) { day in
                    calendarDayCell(day)
                }
            }
        }
        .frame(width: 159, alignment: .topLeading)
    }

    private func calendarDayCell(_ day: CalendarDay) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(day.isToday ? Color.white.opacity(0.18) : Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(day.isToday && day.hasEvents ? Color.green : Color.clear, lineWidth: 1.4)
                )
                .opacity(day.dayNumber == nil ? 0 : 1)

            if let dayNumber = day.dayNumber {
                Text("\(dayNumber)")
                    .font(.system(size: 10, weight: day.isToday ? .bold : .medium))
                    .foregroundStyle(.white.opacity(day.isToday ? 1 : 0.76))

                if day.hasEvents && !day.isToday {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 3, height: 3)
                        .offset(y: -2.5)
                }
            }
        }
        .frame(width: 21, height: 18)
    }

    private var upcomingEvents: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Calendar", systemImage: "calendar")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.80))

            if model.calendarItems.isEmpty {
                Text(model.calendarStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            } else {
                ForEach(model.calendarItems.prefix(2)) { item in
                    Button {
                        model.openCalendar(for: item)
                    } label: {
                        HStack(spacing: 8) {
                            Text(item.timeText)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.50))
                                .frame(width: 39, alignment: .leading)

                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.82))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notificationCentre: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Label("Notification Center", systemImage: "bell.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.80))

                Spacer(minLength: 6)

                Text(model.gmailPageText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)

                gmailRefreshButton
            }

            if !model.gmailInboxMessages.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    gmailInboxList
                }
                .scrollIndicators(.visible)
                .frame(height: 44, alignment: .top)
            } else if model.notifications.isEmpty {
                Text(model.notificationStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    notificationList
                }
                .scrollIndicators(.visible)
                .frame(height: 38, alignment: .top)
            }
        }
    }

    private var gmailRefreshButton: some View {
        Button {
            model.reloadGmailInbox()
        } label: {
            Image(systemName: model.isGmailLoading ? "hourglass" : "arrow.clockwise")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(model.isGmailLoading ? 0.32 : 0.74))
                .frame(width: 17, height: 17)
                .background(
                    Circle()
                        .fill(Color.white.opacity(model.isGmailLoading ? 0.025 : 0.07))
                )
        }
        .buttonStyle(.plain)
        .disabled(model.isGmailLoading)
    }

    private var notificationList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.notifications) { notification in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 7) {
                        Text(notification.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineLimit(1)

                        Spacer(minLength: 6)

                        Text(notification.timeText)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Text(notification.body)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.58))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.trailing, 8)
    }

    private var gmailInboxList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(model.gmailInboxMessages) { message in
                HStack(spacing: 6) {
                    Text(message.senderDisplayName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                        .frame(width: 54, alignment: .leading)

                    Text(message.subject.isEmpty ? "New email" : message.subject)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            if model.canLoadNextGmailPage {
                Button {
                    model.loadNextGmailPage()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.isGmailLoading ? "hourglass" : "plus")
                            .font(.system(size: 8, weight: .bold))

                        Text(model.isGmailLoading ? "Loading" : "Load more")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(model.isGmailLoading ? 0.36 : 0.64))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(model.isGmailLoading)
                .padding(.top, 2)
            }
        }
        .padding(.trailing, 8)
    }

    private var clipboardPreview: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.hasClipboardText ? Color.green.opacity(0.90) : Color.white.opacity(0.42))
                .frame(width: 14)

            Text(model.clipboardText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(model.hasClipboardText ? 0.72 : 0.45))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
