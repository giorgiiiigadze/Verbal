//
//  ScheduleView.swift
//  Verbal
//
//  The working diary: every booked visit, the next useful action for it, and
//  the shortest route from arriving at a job to recording its quote.
//

import SwiftUI

struct ScheduleView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Store.self) private var store
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.openURL) private var openURL

    @Binding var showCreate: Bool
    @Binding var recordingVisit: ScheduledVisit?

    /// The quote selected from a recorded visit. An item destination is used
    /// because this view sits inside the tab's navigation stack; appending to
    /// an unbound local path changed state but gave that stack nothing to push.
    @State private var quoteToOpen: QuoteSummary?
    @State private var selectedVisit: ScheduledVisit?
    @State private var editor: VisitEditor?
    @State private var visitToDelete: ScheduledVisit?
    @State private var filter: ScheduleFilter = .toQuote
    @State private var toast: Toast?

    private enum VisitEditor: Identifiable {
        case new
        case existing(ScheduledVisit)

        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let visit): return visit.id.uuidString
            }
        }
    }

    private enum ScheduleFilter: String, CaseIterable, Identifiable {
        case toQuote
        case all
        case recorded

        var id: String { rawValue }

        var label: String {
            switch self {
            case .toQuote: return "To quote"
            case .all: return "All visits"
            case .recorded: return "Recorded"
            }
        }
    }

    private var visits: [ScheduledVisit] { session.visitStore.visits }

    private var filteredVisits: [ScheduledVisit] {
        visits.filter { visit in
            let matchesFilter: Bool
            switch filter {
            case .toQuote: matchesFilter = !hasRecordedQuote(for: visit)
            case .all: matchesFilter = true
            case .recorded: matchesFilter = hasRecordedQuote(for: visit)
            }

            return matchesFilter
        }
    }

    private var visitGroups: [(day: Date, visits: [ScheduledVisit])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredVisits) {
            calendar.startOfDay(for: $0.date)
        }
        return grouped.keys.sorted().map { day in
            (day, grouped[day, default: []].sorted { $0.date < $1.date })
        }
    }

    var body: some View {
        Group {
            if visits.isEmpty && !session.visitStore.hasCompletedInitialSync {
                loadingState
            } else if visits.isEmpty {
                emptyState
            } else if filteredVisits.isEmpty {
                noMatchesState
            } else {
                agenda
            }
        }
        .background(Color(.homeBackground))
        .navigationTitle("Visits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Show", selection: $filter) {
                        ForEach(ScheduleFilter.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    Image(.homeFilter)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                }
                .accessibilityLabel("Filter schedule")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = .new } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Book a visit")
            }
        }
        .navigationDestination(item: $quoteToOpen) { quote in
            QuoteDetailView(
                quote: liveQuote(quote),
                initialLineItems: session.lineItems(for: quote.id) ?? [],
                onDeleted: {
                    let unlinked = session.visitStore.unlink(fromDeletedQuote: quote.id)
                    Task {
                        for visit in unlinked {
                            await ScheduledVisitNotifications.schedule(visit)
                        }
                    }
                },
                onNeedsRefresh: { Task { await session.refreshQuotes() } }
            )
            .environment(session)
            .environment(store)
            .environment(network)
        }
        .sheet(item: $selectedVisit) { visit in
            let current = liveVisit(visit)
            VisitActionSheet(
                visit: current,
                action: visitAction(for: current),
                onPrimary: { performPrimaryAction(for: current) },
                onDirections: { openDirections(for: current) },
                onCall: { callClient(for: current) },
                onReschedule: { editor = .existing(current) },
                onCancel: { visitToDelete = current },
                onDidNotHappen: { remove(current) },
                onOpenQuote: { openRecordedQuote(for: current) }
            )
        }
        // Booking and rescheduling share the same full-page wizard. A visit
        // has enough detail that the agenda should not remain visible beneath
        // a short sheet while it is being edited.
        .fullScreenCover(item: $editor) { editor in
            switch editor {
            case .new:
                ScheduleVisitSheet(onSave: addOrUpdate)
            case .existing(let visit):
                ScheduleVisitSheet(editing: visit,
                                   onSave: addOrUpdate,
                                   onDelete: remove)
            }
        }
        .alert("Remove this visit?", isPresented: Binding(
            get: { visitToDelete != nil },
            set: { if !$0 { visitToDelete = nil } }
        ), presenting: visitToDelete) { visit in
            Button("Remove", role: .destructive) { remove(visit) }
            Button("Cancel", role: .cancel) {}
        } message: { visit in
            Text("“\(visit.title)” comes off your schedule. Any quote you've already made is untouched.")
        }
        .task {
            session.visitStore.refresh()
            await session.visitStore.sync()
        }
        .refreshable {
            await session.visitStore.sync()
            await session.refreshQuotes()
        }
        .toast($toast)
    }

    private var agenda: some View {
        List {
            ForEach(visitGroups, id: \.day) { group in
                Text(dayHeader(for: group.day))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 2, trailing: 20))

                ForEach(group.visits) { visit in
                    UpcomingVisitCardRow(
                        visit: visit,
                        statusColor: statusColor(for: visit),
                        statusLabel: statusLabel(for: visit),
                        onTap: { selectedVisit = visit }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if hasRecordedQuote(for: visit) {
                            Button { openRecordedQuote(for: visit) } label: {
                                Label("Open quote", systemImage: "doc.text")
                            }
                            .tint(Color(.statusAcceptedText))
                        } else {
                            Button { beginRecording(for: visit) } label: {
                                Label("Record", systemImage: "mic.fill")
                            }
                            .tint(Color(.royalBlue500))
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { visitToDelete = visit } label: {
                            Label("Remove", systemImage: "trash")
                        }
                        .tint(.red)

                        Button { editor = .existing(visit) } label: {
                            Label("Reschedule", systemImage: "calendar.badge.clock")
                        }
                        .tint(Color(.statusMutedText))
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 76, for: .scrollContent)
    }

    private var loadingState: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                skeletonBar(width: 64, height: 14)
                    .padding(.bottom, 2)
                visitSkeleton(titleWidth: 166, detailWidth: 122)
                visitSkeleton(titleWidth: 142, detailWidth: 96)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 76)
        }
        .shimmer(active: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading your visits")
    }

    private func visitSkeleton(titleWidth: CGFloat, detailWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                skeletonBar(width: titleWidth, height: 15)
                skeletonBar(width: detailWidth, height: 11)
            }
            Spacer(minLength: 0)
            skeletonBar(width: 62, height: 20)
        }
        .padding(16)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private func skeletonBar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color(.separator))
            .frame(width: width, height: height)
    }

    private var emptyState: some View {
        EmptyStateMessage(
            icon: "calendar",
            assetIcon: "VisitsEmpty",
            title: "Nothing booked in",
            message: "Add the visits you've got coming up and each one will be ready for directions, a call, or a quote."
        ) {
            EmptyStatePill(title: "Book a visit", icon: "plus") { editor = .new }
        }
    }

    private var noMatchesState: some View {
        EmptyStateMessage(
            icon: "line.3.horizontal.decrease.circle",
            assetIcon: "VisitsNoMatches",
            title: "No visits here",
            message: "Choose another filter to see the rest of your visits."
        ) {
            EmptyStatePill(title: "Show all visits", icon: "calendar") { filter = .all }
        }
    }

    private func dayHeader(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private func liveVisit(_ visit: ScheduledVisit) -> ScheduledVisit {
        visits.first { $0.id == visit.id } ?? visit
    }

    private func liveQuote(_ quote: QuoteSummary) -> QuoteSummary {
        session.quotes.first { $0.id == quote.id } ?? quote
    }

    private func recordedQuote(for visit: ScheduledVisit) -> QuoteSummary? {
        if let id = visit.recordedQuoteId {
            return session.quotes.first { $0.id == id }
        }
        let title = visit.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !title.isEmpty else { return nil }
        return session.quotes.first { quote in
            Calendar.current.isDate(quote.createdAt, inSameDayAs: visit.date)
                && (quote.displayTitle.lowercased() == title
                    || quote.clientName?.lowercased() == title)
        }
    }

    private func hasRecordedQuote(for visit: ScheduledVisit) -> Bool {
        // The relationship is authoritative. The quote list can briefly lag a
        // successful save, or a refresh can fail, neither of which should turn
        // a completed visit back into an invitation to record it again.
        visit.recordedQuoteId != nil || recordedQuote(for: visit) != nil
    }

    private func statusColor(for visit: ScheduledVisit) -> Color {
        if hasRecordedQuote(for: visit) { return Color(.statusAcceptedText) }
        if Date() >= visit.date.addingTimeInterval(2 * 60 * 60) {
            return Color(.statusDeclinedText)
        }
        return Color(.statusWarningText)
    }

    private func statusLabel(for visit: ScheduledVisit) -> String {
        if hasRecordedQuote(for: visit) { return "Recorded" }
        if Date() >= visit.date.addingTimeInterval(2 * 60 * 60) { return "Overdue" }
        return "Scheduled"
    }

    private func visitAction(for visit: ScheduledVisit) -> VisitAction {
        if hasRecordedQuote(for: visit) { return .recorded(recordedQuote(for: visit)) }
        let now = Date()
        if now >= visit.date.addingTimeInterval(-15 * 60),
           now <= visit.date.addingTimeInterval(30 * 60) {
            return .happeningNow
        }
        return visit.date < now ? .passed : .future
    }

    private func performPrimaryAction(for visit: ScheduledVisit) {
        switch visitAction(for: visit) {
        case .future: openDirections(for: visit)
        case .happeningNow, .passed: beginRecording(for: visit)
        case .recorded: openRecordedQuote(for: visit)
        }
    }

    private func addOrUpdate(_ visit: ScheduledVisit) {
        let isEditing = visits.contains { $0.id == visit.id }
        session.visitStore.addOrUpdate(visit)
        Task { await ScheduledVisitNotifications.schedule(visit) }
        toast = Toast(style: .success,
                      message: isEditing ? "Visit saved" : "Visit booked")
    }

    private func remove(_ visit: ScheduledVisit) {
        selectedVisit = nil
        session.visitStore.remove(visit)
        ScheduledVisitNotifications.cancel(visit)
        toast = Toast(style: .success, message: "Visit removed")
    }

    private func beginRecording(for visit: ScheduledVisit) {
        selectedVisit = nil
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            recordingVisit = visit
            showCreate = true
        }
    }

    private func openRecordedQuote(for visit: ScheduledVisit) {
        selectedVisit = nil
        Task {
            if let quote = recordedQuote(for: visit) {
                await presentRecordedQuote(quote)
                return
            }

            // A linked visit can arrive before the quote list does. Refresh
            // once before reporting an error, rather than offering a duplicate
            // recording action for a quote that has already been saved.
            await session.refreshQuotes()
            guard let quote = recordedQuote(for: visit) else {
                toast = Toast(style: .error, message: "Couldn't find that quote")
                return
            }
            await presentRecordedQuote(quote)
        }
    }

    private func presentRecordedQuote(_ quote: QuoteSummary) async {
        await session.prefetchLineItems(for: quote.id)
        try? await Task.sleep(for: .seconds(0.3))
        quoteToOpen = quote
    }

    private func openDirections(for visit: ScheduledVisit) {
        guard let address = visit.address?.trimmingCharacters(in: .whitespacesAndNewlines),
              !address.isEmpty,
              let encoded = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(encoded)") else {
            toast = Toast(style: .error, message: "No address saved")
            return
        }
        openURL(url)
    }

    private func callClient(for visit: ScheduledVisit) {
        guard let phone = visit.phone?.trimmingCharacters(in: .whitespacesAndNewlines),
              !phone.isEmpty else {
            toast = Toast(style: .error, message: "No phone number saved")
            return
        }
        let dialable = phone.filter { $0.isNumber || $0 == "+" }
        guard !dialable.isEmpty, let url = URL(string: "tel:\(dialable)") else {
            toast = Toast(style: .error, message: "Couldn't call this number")
            return
        }
        openURL(url)
    }
}
