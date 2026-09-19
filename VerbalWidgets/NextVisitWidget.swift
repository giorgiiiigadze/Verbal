import SwiftUI
import UIKit
import WidgetKit

enum NextVisitWidgetStore {
    static let appGroup = "group.com.giorgi.verbal"
    static let snapshotKey = "nextVisitWidgetSnapshot"
    struct Snapshot: Codable { let id: UUID; let title: String; let clientName: String?; let date: Date; let endDate: Date; let address: String? }
    struct Payload: Codable { let visits: [Snapshot] }
}

struct NextVisitEntry: TimelineEntry {
    let date: Date
    let visits: [NextVisitWidgetStore.Snapshot]
    var visit: NextVisitWidgetStore.Snapshot? { visits.first }
}

struct NextVisitProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextVisitEntry { .init(date: .now, visits: [.sample, .sampleFollowUp]) }
    func getSnapshot(in context: Context, completion: @escaping (NextVisitEntry) -> Void) { completion(currentEntry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextVisitEntry>) -> Void) {
        // The containing app writes the snapshot and explicitly reloads this
        // timeline whenever bookings change. Keeping this initial timeline
        // stable avoids WidgetKit deferring the first Home Screen render while
        // it reconciles a near-term calendar refresh request.
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }
    private func currentEntry() -> NextVisitEntry {
        let data = UserDefaults(suiteName: NextVisitWidgetStore.appGroup)?.data(forKey: NextVisitWidgetStore.snapshotKey)
        let visits = data.flatMap { try? JSONDecoder().decode(NextVisitWidgetStore.Payload.self, from: $0) }?.visits
            ?? data.flatMap { try? JSONDecoder().decode(NextVisitWidgetStore.Snapshot.self, from: $0) }.map { [$0] } ?? []
        return .init(date: .now, visits: visits)
    }
}

struct NextVisitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextVisitEntry
    private let blue = Color(red: 52 / 255, green: 80 / 255, blue: 196 / 255)
    private let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1) : .white })
    private let visitAmber = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 163 / 255, blue: 68 / 255, alpha: 1)
            : UIColor(red: 217 / 255, green: 115 / 255, blue: 13 / 255, alpha: 1)
    })
    private let visitAmberFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 217 / 255, green: 115 / 255, blue: 13 / 255, alpha: 0.20)
            : UIColor(red: 250 / 255, green: 235 / 255, blue: 221 / 255, alpha: 1)
    })
    var body: some View {
        Group { if let visit = entry.visit { content(visit) } else { empty } }
            // The reference uses a deliberately tighter inset than WidgetKit's
            // standard small-widget margin. Other widget families retain it.
            .padding(family == .systemSmall ? 0 : 16)
            .containerBackground(for: .widget) { surface }
            .widgetURL(entry.visit.map(url) ?? URL(string: "verbal://calendar")!)
    }

    @ViewBuilder private func content(_ visit: NextVisitWidgetStore.Snapshot) -> some View {
        switch family {
        case .accessoryCircular: Image(systemName: "calendar.badge.clock").widgetLabel { Text(visit.date, style: .timer) }
        case .accessoryInline: Text("Next: \(visit.title) · \(visit.date, style: .time)")
        case .accessoryRectangular: lockScreen(visit)
        case .systemMedium: medium(visit, upcoming: Array(entry.visits.dropFirst()))
        case .systemLarge: large(visit, upcoming: Array(entry.visits.dropFirst()))
        default: small(visit, upcoming: Array(entry.visits.dropFirst()))
        }
    }

    private func medium(_ visit: NextVisitWidgetStore.Snapshot, upcoming: [NextVisitWidgetStore.Snapshot]) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                HStack(alignment: .top, spacing: 12) {
                    mediumCurrentQuote(visit)
                        .frame(width: proxy.size.width * 0.43, alignment: .leading)
                        .frame(maxHeight: .infinity, alignment: .top)

                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1)
                        .padding(.vertical, 5)

                    mediumUpcomingQuotes(upcoming)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }

                Image("VisitsEmpty")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .frame(width: 42, height: 42)
                    .padding(.bottom, 4)
            }
        }
    }

    private func mediumCurrentQuote(_ visit: NextVisitWidgetStore.Snapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(visitDateLabel(for: visit.date))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary)
            Text(visit.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(timeRange(for: visit))
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func mediumUpcomingQuotes(_ quotes: [NextVisitWidgetStore.Snapshot]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Next visit")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary)

            if quotes.isEmpty {
                Text("Nothing else booked")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "calendar.badge.checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.secondary)
                    .padding(.bottom, 2)
            } else {
                ForEach(Array(quotes.prefix(3)), id: \.id) { quote in
                    HStack(alignment: .top, spacing: 7) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(quote.date, format: .dateTime.day())
                                .font(.caption.weight(.bold).monospacedDigit())
                            Text(weekday(for: quote.date))
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(Color.primary)
                        .frame(width: 25, alignment: .leading)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(quote.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(timeRange(for: quote))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func large(_ visit: NextVisitWidgetStore.Snapshot, upcoming: [NextVisitWidgetStore.Snapshot]) -> some View {
        VStack(spacing: 0) {
            summaryPanel(visit, compact: false)
                .frame(maxWidth: .infinity)
                .frame(height: 158)

            Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1)
                .padding(.horizontal, 16)

            itinerary(upcoming, limit: 3, compact: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func summaryPanel(_ visit: NextVisitWidgetStore.Snapshot,
                              compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            calendarVisitCard(visit, compact: compact)
                .frame(maxHeight: .infinity)
        }
        .padding(compact ? 6 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func calendarVisitCard(_ visit: NextVisitWidgetStore.Snapshot,
                                   compact: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)

        return VStack(alignment: .leading, spacing: 2) {
            Text(visitDateLabel(for: visit.date))
                .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                .lineLimit(1)
                .padding(.bottom, compact ? 2 : 4)
            Text(visit.title)
                .font((compact ? Font.caption : Font.subheadline).weight(.semibold))
                .lineLimit(1)
            Text(timeRange(for: visit))
                .font(compact ? .caption2 : .caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(visitAmber)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, compact ? 10 : 13)
        .padding(.trailing, 6)
        .padding(.vertical, compact ? 5 : 8)
        .background(visitAmberFill, in: shape)
        .overlay(alignment: .leading) {
            Rectangle().fill(visitAmber).frame(width: compact ? 3 : 4)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(visitAmber.opacity(0.18), lineWidth: 0.5))
    }

    private func visitDateLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func itinerary(_ visits: [NextVisitWidgetStore.Snapshot], limit: Int, compact: Bool) -> some View {
        let displayed = Array(visits.prefix(limit))

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, item in
                row(item, compact: compact)
                if index < displayed.count - 1 {
                    Spacer(minLength: compact ? 4 : 8)
                }
            }

            if displayed.isEmpty {
                Text("No more visits booked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
                Spacer(minLength: 0)
            }
        }
        .padding(compact ? 6 : 8)
    }

    private func row(_ visit: NextVisitWidgetStore.Snapshot, compact: Bool = false) -> some View {
        let primaryFont: Font = .system(size: compact ? 15 : 17)
        let metadataFont: Font = .system(size: compact ? 12.5 : 13.5)

        return HStack(alignment: .top, spacing: compact ? 7 : 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(visit.date, format: .dateTime.day())
                    .font(primaryFont.weight(.bold).monospacedDigit())
                    .lineLimit(1)
                Text(weekday(for: visit.date))
                    .font(metadataFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: compact ? 26 : 34, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .leading, spacing: 2) {
                Text(visit.title)
                    .font(primaryFont.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(timeRange(for: visit))
                    .font(metadataFont)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private func timeRange(for visit: NextVisitWidgetStore.Snapshot) -> String {
        let start = Self.clockFormatter.string(from: visit.date)
        let end = Self.clockFormatter.string(from: visit.endDate)
        return "\(start) – \(end)"
    }

    private func weekday(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()


    private func small(_ visit: NextVisitWidgetStore.Snapshot,
                       upcoming: [NextVisitWidgetStore.Snapshot]) -> some View {
        let allQuotes = [visit] + upcoming
        let quotes = Array(allQuotes.prefix(3))
        let remainingCount = allQuotes.count - quotes.count

        return VStack(spacing: 0) {
            Text(Date.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.primary.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .padding(.bottom, 11)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(quotes, id: \.id) { quote in
                    HStack(alignment: .top, spacing: 9) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color(.statusWarningText))
                            .frame(width: 4, height: 32)

                        VStack(alignment: .leading, spacing: 0) {
                            Text(quote.title)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text(timeRange(for: quote))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if remainingCount > 0 {
                    Text("+\(remainingCount) more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .padding(.leading, 13)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .foregroundStyle(Color.primary)
    }

    private func lockScreen(_ visit: NextVisitWidgetStore.Snapshot) -> some View { VStack(alignment: .leading, spacing: 2) { Text("Next Visit").font(.caption2.weight(.bold)); Text(visit.title).font(.headline).lineLimit(1); Text(visit.date, format: .dateTime.weekday(.abbreviated).hour().minute()).font(.caption).foregroundStyle(.secondary) } }

    @ViewBuilder private var empty: some View {
        switch family {
        case .systemSmall:
            emptySmall
        case .systemMedium:
            emptyMedium
        default:
            emptyStandard
        }
    }

    private var emptySmall: some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 5) {
                Image("VisitsEmpty")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                Text("No visits booked")
                    .font(.caption.weight(.bold))
                Text("Your next job will appear here")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
    }

    private var emptyMedium: some View {
        HStack(spacing: 14) {
            Image("VisitsEmpty")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(Color.primary.opacity(0.78))
                .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 5) {
                Text("No visits booked")
                    .font(.headline.weight(.bold))
                Text("Your upcoming jobs will appear here once they are booked.")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(3)
                openCalendarLabel(color: Color.primary)
                    .padding(.top, 2)
            }
            .foregroundStyle(Color.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var emptyStandard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Next Visit", systemImage: "calendar")
                .font(.caption.weight(.bold))
                .foregroundStyle(blue)
            Spacer()
            Text("No visit booked").font(.headline)
            Text("Your next job will appear here.").font(.caption).foregroundStyle(.secondary)
            openCalendarLabel(color: blue)
        }
        .padding(6)
    }

    private func openCalendarLabel(color: Color) -> some View {
        HStack(spacing: 4) {
            Text("Open Calendar")
            Image("OpenCalendarArrow")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(color)
    }
    private func clean(_ value: String?) -> String? { let value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return value.isEmpty ? nil : value }
    private func url(_ visit: NextVisitWidgetStore.Snapshot) -> URL { URL(string: "verbal://visit/\(visit.id.uuidString)")! }
}

extension NextVisitWidgetStore.Snapshot {
    static let sample = Self(id: UUID(), title: "Bathroom survey", clientName: "Mrs Patel", date: .now.addingTimeInterval(3600), endDate: .now.addingTimeInterval(7200), address: "18 Kings Road")
    static let sampleFollowUp = Self(id: UUID(), title: "Kitchen measure-up", clientName: "Sam Wright", date: .now.addingTimeInterval(86400), endDate: .now.addingTimeInterval(90000), address: "7 Orchard Lane")
}

@main struct VerbalWidgetsBundle: WidgetBundle { var body: some Widget { NextVisitWidget() } }
struct NextVisitWidget: Widget { let kind = "NextVisitWidget"; var body: some WidgetConfiguration { StaticConfiguration(kind: kind, provider: NextVisitProvider()) { NextVisitWidgetView(entry: $0) }.configurationDisplayName("Next visit").description("See your next booked job at a glance.").supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline]).contentMarginsDisabled() } }
