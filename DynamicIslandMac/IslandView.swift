import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: model.isExpanded ? 24 : 18, style: .continuous)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: model.isExpanded ? 18 : 15, style: .continuous)
                        .stroke(Color.white.opacity(model.isExpanded ? 0.10 : 0.06), lineWidth: 1)
                )

            if model.isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } 
        }
        .animation(.snappy(duration: 0.18), value: model.isExpanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.timeText)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Spacer()

                Text(model.dateText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }

            HStack(spacing: 10) {
                Image(systemName: model.isMusicPlaying ? "music.note" : "speaker.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.isMusicPlaying ? Color.green : Color.white.opacity(0.48))
                    .frame(width: 20)

                Text(model.musicText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(model.isMusicPlaying ? 0.92 : 0.62))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 5) {
                    if model.calendarItems.isEmpty {
                        Text(model.calendarStatusText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(1)
                    } else {
                        ForEach(model.calendarItems) { item in
                            HStack(spacing: 7) {
                                Text(item.timeText)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.54))
                                    .frame(width: 44, alignment: .leading)

                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 17)
        .padding(.bottom, 16)
    }
}
