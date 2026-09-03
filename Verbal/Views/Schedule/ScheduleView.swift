import SwiftUI

/// A working-day view of locally cached visits. Booking and actions deliberately
/// remain in the existing sheets, so this is a presentation change only.
struct ScheduleView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Store.self) private var store
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.openURL) private var openURL
    @Binding var showCreate: Bool
    @Binding var recordingVisit: ScheduledVisit?

    @State private var quoteToOpen: QuoteSummary?
    @State private var selectedVisit: ScheduledVisit?
    @State private var editor: VisitEditor?
    @State private var visitToDelete: ScheduledVisit?
    @State private var filter: ScheduleFilter = .all
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var toast: Toast?

    private enum VisitEditor: Identifiable { case new, existing(ScheduledVisit); var id: String { switch self { case .new: return "new"; case .existing(let visit): return visit.id.uuidString } } }
    private enum ScheduleFilter: String, CaseIterable, Identifiable {
        case toQuote, all, recorded
        var id: String { rawValue }
        var label: String { switch self { case .toQuote: return "To quote"; case .all: return "All visits"; case .recorded: return "Recorded" } }
    }

    private var visits: [ScheduledVisit] { session.visitStore.visits }
    private var filteredVisits: [ScheduledVisit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return visits.filter { visit in
            let matches = switch filter { case .toQuote: !hasRecordedQuote(for: visit); case .all: true; case .recorded: hasRecordedQuote(for: visit) }
            return matches && (query.isEmpty || visit.title.localizedCaseInsensitiveContains(query) || (visit.clientName?.localizedCaseInsensitiveContains(query) ?? false) || (visit.address?.localizedCaseInsensitiveContains(query) ?? false))
        }
    }
    private var dayVisits: [ScheduledVisit] { filteredVisits.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }.sorted { $0.date < $1.date } }

    var body: some View {
        Group {
            if visits.isEmpty && !session.visitStore.hasCompletedInitialSync { loadingState }
            else { calendar }
        }
        .background(Color(.homeBackground))
        .navigationTitle("Calendar").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(.homeBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .modifier(SearchWhenAsked(isActive: isSearching, text: $searchText, isPresented: $isSearching, prompt: "Search calendar"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button { isSearching = true } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search visits")
                Menu { Picker("Show", selection: $filter) { ForEach(ScheduleFilter.allCases) { Text($0.label).tag($0) } } } label: { Image(.homeFilter).resizable().scaledToFit().frame(width: 22, height: 22) }.accessibilityLabel("Filter visits")
            }
            ToolbarItem(placement: .topBarTrailing) { Button { editor = .new } label: { Image(systemName: "plus") }.accessibilityLabel("Book a visit") }
        }
        .navigationDestination(item: $quoteToOpen) { quote in
            QuoteDetailView(quote: liveQuote(quote), initialLineItems: session.lineItems(for: quote.id) ?? [], onDeleted: {
                let unlinked = session.visitStore.unlink(fromDeletedQuote: quote.id)
                Task { for visit in unlinked { await ScheduledVisitNotifications.schedule(visit) } }
            }, onNeedsRefresh: { Task { await session.refreshQuotes() } }).environment(session).environment(store).environment(network)
        }
        .sheet(item: $selectedVisit) { visit in
            let current = liveVisit(visit)
            VisitActionSheet(visit: current, action: visitAction(for: current), onPrimary: { performPrimaryAction(for: current) }, onDirections: { openDirections(for: current) }, onCall: { callClient(for: current) }, onReschedule: { editor = .existing(current) }, onCancel: { visitToDelete = current }, onDidNotHappen: { remove(current) }, onOpenQuote: { openRecordedQuote(for: current) })
        }
        .sheet(item: $editor) { editor in
            switch editor { case .new: ScheduleVisitSheet(onSave: addOrUpdate).presentationDetents([.large]).presentationDragIndicator(.hidden); case .existing(let visit): ScheduleVisitSheet(editing: visit, onSave: addOrUpdate, onDelete: remove).presentationDetents([.large]).presentationDragIndicator(.hidden) }
        }
        .alert("Remove this visit?", isPresented: Binding(get: { visitToDelete != nil }, set: { if !$0 { visitToDelete = nil } }), presenting: visitToDelete) { visit in Button("Remove", role: .destructive) { remove(visit) }; Button("Cancel", role: .cancel) {} } message: { visit in Text("“\(visit.title)” comes off your schedule. Any quote you've already made is untouched.") }
        .task { session.visitStore.refresh(); await session.visitStore.sync() }
        .refreshable { await session.visitStore.sync(); await session.refreshQuotes() }
        .toast($toast)
    }

    private var calendar: some View {
        VStack(spacing: 0) {
            VisitsDaySelector(selectedDay: $selectedDay)
                .zIndex(1)
            VisitsTimelineView(day: selectedDay,
                               visits: dayVisits,
                               status: calendarStatus) { selectedVisit = $0 }
                // Keep the scrolled grid from visually touching the day header.
                .padding(.top, 10)
        }
    }
    private var loadingState: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 10) { RoundedRectangle(cornerRadius: 7).fill(Color(.separator)).frame(width: 116, height: 20); ForEach(0..<5, id: \.self) { _ in RoundedRectangle(cornerRadius: 14).fill(Color(.cardSurface)).frame(height: 68).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(.separator), lineWidth: 0.5)) } }.padding(20) }.shimmer(active: true).accessibilityLabel("Loading your visits")
    }
    private func liveVisit(_ visit: ScheduledVisit) -> ScheduledVisit { visits.first { $0.id == visit.id } ?? visit }
    private func liveQuote(_ quote: QuoteSummary) -> QuoteSummary { session.quotes.first { $0.id == quote.id } ?? quote }
    private func recordedQuote(for visit: ScheduledVisit) -> QuoteSummary? {
        if let id = visit.recordedQuoteId { return session.quotes.first { $0.id == id } }
        let key = visit.clientKey; guard !key.isEmpty else { return nil }
        return session.quotes.first { Calendar.current.isDate($0.createdAt, inSameDayAs: visit.date) && ($0.displayTitle.lowercased() == key || $0.clientName?.lowercased() == key) }
    }
    private func hasRecordedQuote(for visit: ScheduledVisit) -> Bool { visit.recordedQuoteId != nil || recordedQuote(for: visit) != nil }
    private func calendarStatus(for visit: ScheduledVisit) -> CalendarVisitStatus {
        if hasRecordedQuote(for: visit) { return .recorded }
        // Match Home's Upcoming card: once a visit has been underway for two
        // hours without a recorded quote, it needs attention even if its
        // booked duration has not ended yet. Using `endDate` here left the
        // same visit amber in Calendar and red on Home.
        return Date() >= visit.date.addingTimeInterval(2 * 60 * 60)
            ? .overdue
            : .upcoming
    }
    private func visitAction(for visit: ScheduledVisit) -> VisitAction { if hasRecordedQuote(for: visit) { return .recorded(recordedQuote(for: visit)) }; let now = Date(); if now >= visit.date.addingTimeInterval(-900), now <= visit.date.addingTimeInterval(1800) { return .happeningNow }; return visit.date < now ? .passed : .future }
    private func addOrUpdate(_ visit: ScheduledVisit) { let editing = visits.contains { $0.id == visit.id }; session.visitStore.addOrUpdate(visit); Task { await ScheduledVisitNotifications.schedule(visit) }; toast = Toast(style: .success, message: editing ? "Visit saved" : "Visit booked") }
    private func remove(_ visit: ScheduledVisit) { selectedVisit = nil; session.visitStore.remove(visit); ScheduledVisitNotifications.cancel(visit); toast = Toast(style: .success, message: "Visit removed") }
    private func performPrimaryAction(for visit: ScheduledVisit) { switch visitAction(for: visit) { case .future: openDirections(for: visit); case .happeningNow, .passed: beginRecording(for: visit); case .recorded: openRecordedQuote(for: visit) } }
    private func beginRecording(for visit: ScheduledVisit) { selectedVisit = nil; Task { try? await Task.sleep(for: .seconds(0.3)); recordingVisit = visit; showCreate = true } }
    private func openRecordedQuote(for visit: ScheduledVisit) { selectedVisit = nil; Task { if let quote = recordedQuote(for: visit) { await presentRecordedQuote(quote); return }; await session.refreshQuotes(); guard let quote = recordedQuote(for: visit) else { toast = Toast(style: .error, message: "Couldn't find that quote"); return }; await presentRecordedQuote(quote) } }
    private func presentRecordedQuote(_ quote: QuoteSummary) async { await session.prefetchLineItems(for: quote.id); try? await Task.sleep(for: .seconds(0.3)); quoteToOpen = quote }
    private func openDirections(for visit: ScheduledVisit) { guard let address = visit.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty, let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else { toast = Toast(style: .error, message: "No address saved"); return }; openURL(url) }
    private func callClient(for visit: ScheduledVisit) { guard let phone = visit.phone?.trimmingCharacters(in: .whitespacesAndNewlines), !phone.isEmpty else { toast = Toast(style: .error, message: "No phone number saved"); return }; let dialable = phone.filter { $0.isNumber || $0 == "+" }; guard !dialable.isEmpty, let url = URL(string: "tel:\(dialable)") else { toast = Toast(style: .error, message: "Couldn't call this number"); return }; openURL(url) }
}

private enum CalendarVisitStatus {
    case upcoming, recorded, overdue

    var textColor: Color {
        switch self {
        case .upcoming: Color(.statusWarningText)
        case .recorded: Color(.statusAcceptedText)
        case .overdue: Color(.statusDeclinedText)
        }
    }

    var fillColor: Color {
        switch self {
        case .upcoming: Color(.statusWarningFill)
        case .recorded: Color(.statusAcceptedFill)
        case .overdue: Color(.statusDeclinedFill)
        }
    }
}

private struct VisitsCalendarHeader: View {
    @Binding var selectedDay: Date
    private let calendar = Calendar.current
    var body: some View {
        HStack(spacing: 2) {
            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").font(.footnote.weight(.semibold)).frame(width: 32, height: 32) }.accessibilityLabel("Previous month")
            Text(selectedDay.formatted(.dateTime.month(.wide).year())).font(.title3.weight(.semibold)).foregroundStyle(Color(.mainText))
            Button { moveMonth(1) } label: { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).frame(width: 32, height: 32) }.accessibilityLabel("Next month")
            Spacer()
            if !calendar.isDateInToday(selectedDay) { Button("Today") { selectedDay = calendar.startOfDay(for: .now) }.font(.footnote.weight(.medium)).foregroundStyle(Color(.royalBlue600)) }
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
    }
    private func moveMonth(_ amount: Int) { selectedDay = calendar.date(byAdding: .month, value: amount, to: selectedDay) ?? selectedDay }
}

private struct VisitsDaySelector: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedDay: Date
    private let calendar = Calendar.current
    var body: some View {
        HStack(spacing: 14) {
            Button { moveDay(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 36, height: 40)
            }
            .accessibilityLabel("Previous day")

            Spacer()
            HStack(spacing: 6) {
                Text(selectedDay.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(isToday ? selectedDayBackground : .clear,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("–")
                    .foregroundStyle(.secondary)
                Text(selectedDay.formatted(.dateTime.weekday(.wide)))
                    .font(.headline.weight(.medium))
            }
            Spacer()

            Button { moveDay(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 36, height: 40)
            }
            .accessibilityLabel("Next day")
        }
        .foregroundStyle(colorScheme == .dark ? .white : Color(.mainText))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(colorScheme == .dark ? Color("DaySelectorBar") : Color(.cardSurface))
        .overlay(alignment: .bottom) {
            if colorScheme != .dark {
                Rectangle()
                    .fill(Color(.separator).opacity(0.65))
                    .frame(height: 0.5)
            }
        }
        .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.06),
                radius: 7,
                y: 3)
        .accessibilityElement(children: .contain)
    }

    private var selectedDayBackground: Color {
        colorScheme == .dark ? .white.opacity(0.16) : Color(.mainText).opacity(0.08)
    }

    private var isToday: Bool {
        calendar.isDateInToday(selectedDay)
    }

    private func moveDay(_ amount: Int) {
        withAnimation(.easeInOut(duration: 0.28)) {
            selectedDay = calendar.date(byAdding: .day, value: amount, to: selectedDay) ?? selectedDay
        }
    }
}

private struct VisitsTimelineView: View {
    let day: Date
    let visits: [ScheduledVisit]
    let status: (ScheduledVisit) -> CalendarVisitStatus
    let onSelect: (ScheduledVisit) -> Void
    // A dedicated left rail keeps the clock readable while the day pages move
    // horizontally. Short labels avoid the two-line time stamps seen in the
    // earlier calendar layout.
    // A fixed gutter gives every hour the same visual anchor and leaves the
    // schedule canvas quiet, without bringing back a visible divider.
    private let hourHeight: CGFloat = 74; private let labelWidth: CGFloat = 78; private let calendar = Calendar.current
    private let overlappingColumnGap: CGFloat = 8
    private var placements: [VisitPlacement] { VisitPlacement.make(from: visits) }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                GeometryReader { geometry in
                let columnWidth = geometry.size.width - labelWidth
                let trackWidth = columnWidth - 12
                ZStack(alignment: .topLeading) {
                    // These rows give ScrollViewReader real layout positions.
                    // The label/grid views below are visually offset inside the
                    // ZStack and cannot reliably act as scroll destinations.
                    VStack(spacing: 0) {
                        // Five-minute anchors let the current-time line land
                        // at the centre of the viewport, rather than merely
                        // centring the beginning of its hour.
                        ForEach(0..<288, id: \.self) { slot in
                            Color.clear
                                .frame(height: hourHeight / 12)
                                .id(slotID(for: slot))
                        }
                    }
                    ForEach(0...24, id: \.self) { hour in
                        Text(hourLabel(hour))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: labelWidth - 12, alignment: .trailing)
                            .padding(.trailing, 12)
                            .offset(y: CGFloat(hour) * hourHeight - 7)
                        Rectangle().fill(Color(.separator).opacity(0.6)).frame(height: 0.5).offset(x: labelWidth, y: CGFloat(hour) * hourHeight)
                    }
                    ForEach(placements) { item in
                        let columnCount = CGFloat(item.columnCount)
                        let width = (trackWidth - overlappingColumnGap * (columnCount - 1)) / columnCount
                        VisitCalendarCard(visit: item.visit, status: status(item.visit))
                            .frame(width: width, height: height(for: item.visit), alignment: .topLeading)
                            .offset(x: labelWidth + 6 + CGFloat(item.column) * (width + overlappingColumnGap),
                                    y: yPosition(item.visit.date) + 4)
                            .onTapGesture { onSelect(item.visit) }
                    }
                    // A periodic timeline keeps the marker live if this page
                    // stays open while the working day moves on.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        CurrentTimeIndicator(date: context.date, labelWidth: labelWidth)
                            .frame(width: geometry.size.width)
                            .offset(y: yPosition(context.date))
                    }
                }.frame(height: hourHeight * 24)
                }.frame(height: hourHeight * 24)
                    // The midnight label sits slightly above its hour rule.
                    // Give it real scroll content above the grid so it cannot
                    // be clipped by the ScrollView's top edge.
                    .padding(.top, 12)
                    .padding(.bottom, 100)
            }
            .task(id: day) {
                // Wait for the scroll content to establish its anchors before
                // moving the viewport; calling in the first layout pass can
                // be ignored by SwiftUI.
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                scrollNearCurrentTime(using: proxy)
            }
        }
    }
    private func scrollNearCurrentTime(using proxy: ScrollViewProxy) {
        // Today should always open as a working "now" view. A visit later in
        // the day must not pull the camera away from the current-time marker.
        if calendar.isDateInToday(day) {
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.32)) {
                    proxy.scrollTo(slotID(for: .now), anchor: .center)
                }
            }
            return
        }

        let reference: Date
        reference = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let nearest = visits.min { abs($0.date.timeIntervalSince(reference)) < abs($1.date.timeIntervalSince(reference)) }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.32)) {
                proxy.scrollTo(slotID(for: nearest?.date ?? reference), anchor: .center)
            }
        }
    }
    private func slotID(for date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return slotID(for: (parts.hour ?? 0) * 12 + (parts.minute ?? 0) / 5)
    }
    private func slotID(for slot: Int) -> String { "timeline-slot-\(slot)" }
    /// A block as tall as the visit is long, so an afternoon that is actually
    /// full looks full. Floored at a readable height — a fifteen-minute call
    /// would otherwise be a strip too short to hold its own name.
    private func height(for visit: ScheduledVisit) -> CGFloat {
        max(34, CGFloat(visit.durationMinutes) / 60 * hourHeight - 8)
    }
    private func yPosition(_ date: Date) -> CGFloat { let p = calendar.dateComponents([.hour, .minute], from: date); return CGFloat((p.hour ?? 0) * 60 + (p.minute ?? 0)) / 60 * hourHeight }
    private func hourLabel(_ hour: Int) -> String {
        guard hour < 24 else { return "" }
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        return date.formatted(.dateTime.hour())
    }
}

private struct VisitPlacement: Identifiable {
    let visit: ScheduledVisit; let column: Int; let columnCount: Int; var id: UUID { visit.id }
    static func make(from visits: [ScheduledVisit]) -> [VisitPlacement] {
        let sorted = visits.sorted {
            $0.date == $1.date ? $0.endDate < $1.endDate : $0.date < $1.date
        }

        // A cluster is one connected set of overlaps. It must be transitive:
        // a visit can bridge two others that do not themselves overlap.
        var clusters: [[ScheduledVisit]] = []
        var clusterEnd: Date?
        for visit in sorted {
            if let currentEnd = clusterEnd, visit.date < currentEnd {
                clusters[clusters.count - 1].append(visit)
                clusterEnd = max(currentEnd, visit.endDate)
            } else {
                clusters.append([visit])
                clusterEnd = visit.endDate
            }
        }

        return clusters.flatMap { cluster in
            // The first column whose previous visit has finished can be reused.
            // Every member receives the final cluster width, not a width based
            // only on the events it directly intersects.
            var columnEnds: [Date] = []
            var assigned: [(visit: ScheduledVisit, column: Int)] = []
            for visit in cluster {
                let column = columnEnds.firstIndex { $0 <= visit.date } ?? columnEnds.count
                if column == columnEnds.count {
                    columnEnds.append(visit.endDate)
                } else {
                    columnEnds[column] = visit.endDate
                }
                assigned.append((visit, column))
            }
            return assigned.map { VisitPlacement(visit: $0.visit,
                                                 column: $0.column,
                                                 columnCount: columnEnds.count) }
        }
    }

}

private struct VisitCalendarCard: View {
    let visit: ScheduledVisit
    let status: CalendarVisitStatus

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(alignment: .leading, spacing: 2) {
            Text(visit.title).font(.caption.weight(.semibold)).lineLimit(1)
            Text(visit.timeRangeText).font(.caption2).lineLimit(1)
            if let client = visit.clientName, !client.isEmpty {
                Text(client).font(.caption2).lineLimit(1)
            } else if let address = visit.address, !address.isEmpty {
                Text(address).font(.caption2).lineLimit(1)
            }
        }
        .foregroundStyle(status.textColor)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(status.fillColor, in: shape)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(status.textColor)
                .frame(width: 4)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(status.textColor.opacity(0.18), lineWidth: 0.5))
    }
}
private struct CurrentTimeIndicator: View {
    let date: Date
    let labelWidth: CGFloat

    var body: some View {
        HStack(spacing: 5) {
            Text(date.formatted(date: .omitted, time: .shortened))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(.mainText))
                .lineLimit(1)
                .frame(width: labelWidth - 12, alignment: .trailing)
                .padding(.trailing, 12)
            Circle().fill(Color(.mainText)).frame(width: 6, height: 6)
            Rectangle().fill(Color(.mainText)).frame(height: 1)
        }
        .accessibilityLabel("Current time, \(date.formatted(date: .omitted, time: .shortened))")
    }
}
