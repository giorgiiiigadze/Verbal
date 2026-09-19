//
//  HomeTimelineList.swift
//  Verbal
//
//  The presentation-only timeline for Home. State, navigation destinations,
//  and mutations remain in HomeView; this view receives the small set of
//  values and actions it needs to render the list.
//

import SwiftUI

private enum HomeTimelineMetrics {
    static let topAnchor = "home-timeline-top"
    static let visitCardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)
}

struct HomeTimelineSection: Identifiable {
    enum Surface: Equatable {
        case warm
        case white

        func color(for colorScheme: ColorScheme) -> Color {
            switch (self, colorScheme) {
            case (.warm, .dark): Color(.cardSurface)
            case (.white, .dark): Color(.homeBackground)
            case (.warm, .light): Color(.homeBackground)
            case (.white, .light): Color(.cardSurface)
            @unknown default: Color(.homeBackground)
            }
        }
    }

    enum Item: Identifiable {
        case quote(QuoteSummary)
        case visit(ScheduledVisit)

        var id: String {
            switch self {
            case .quote(let quote): "quote-\(quote.id.uuidString)"
            case .visit(let visit): "visit-\(visit.id.uuidString)"
            }
        }
    }

    let title: String
    let items: [Item]
    let surface: Surface
    let id: String
}

enum HomeVisitStatus {
    case next
    case upcoming
    case overdue

    var color: Color {
        switch self {
        case .next, .upcoming: Color(.statusWarningText)
        case .overdue: Color(.statusDeclinedText)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .next: "Next visit"
        case .upcoming: "Upcoming visit"
        case .overdue: "Overdue visit"
        }
    }
}

struct HomeVisitPresentation {
    let status: HomeVisitStatus
    let detail: String?
}

struct HomeTimelineList<QuoteMenu: View>: View {
    let sections: [HomeTimelineSection]
    let showsUpcomingVisitsEmptyCard: Bool
    let colorScheme: ColorScheme
    let scrollToTopToken: Int
    let unpricedCount: (QuoteSummary) -> Int?
    let onPrefetchQuote: (QuoteSummary) -> Void
    let onDeleteQuote: (QuoteSummary) -> Void
    let onSelectVisit: (ScheduledVisit) -> Void
    let onDeleteVisit: (ScheduledVisit) -> Void
    let visitPresentation: (ScheduledVisit) -> HomeVisitPresentation
    let quoteMenu: (QuoteSummary) -> QuoteMenu

    init(
        sections: [HomeTimelineSection],
        showsUpcomingVisitsEmptyCard: Bool,
        colorScheme: ColorScheme,
        scrollToTopToken: Int,
        unpricedCount: @escaping (QuoteSummary) -> Int?,
        onPrefetchQuote: @escaping (QuoteSummary) -> Void,
        onDeleteQuote: @escaping (QuoteSummary) -> Void,
        onSelectVisit: @escaping (ScheduledVisit) -> Void,
        onDeleteVisit: @escaping (ScheduledVisit) -> Void,
        visitPresentation: @escaping (ScheduledVisit) -> HomeVisitPresentation,
        @ViewBuilder quoteMenu: @escaping (QuoteSummary) -> QuoteMenu
    ) {
        self.sections = sections
        self.showsUpcomingVisitsEmptyCard = showsUpcomingVisitsEmptyCard
        self.colorScheme = colorScheme
        self.scrollToTopToken = scrollToTopToken
        self.unpricedCount = unpricedCount
        self.onPrefetchQuote = onPrefetchQuote
        self.onDeleteQuote = onDeleteQuote
        self.onSelectVisit = onSelectVisit
        self.onDeleteVisit = onDeleteVisit
        self.visitPresentation = visitPresentation
        self.quoteMenu = quoteMenu
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                pageTitle

                if showsUpcomingVisitsEmptyCard {
                    upcomingVisitsEmptyCard
                }

                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    sectionTitle(section.title, surface: section.surface)

                    ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                        let closesWarmSurface = section.surface == .warm
                            && sections.indices.contains(index + 1)
                            && sections[index + 1].surface == .white
                            && itemIndex == section.items.indices.last

                        switch item {
                        case .quote(let quote):
                            quoteTimelineRow(quote, surface: section.surface)
                        case .visit(let visit):
                            visitRow(
                                visit,
                                surface: section.surface,
                                bottomInset: closesWarmSurface ? 20 : 5
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 88, for: .scrollContent)
            .onChange(of: scrollToTopToken) { _, _ in
                withAnimation(.snappy(duration: 0.35)) {
                    proxy.scrollTo(HomeTimelineMetrics.topAnchor, anchor: .top)
                }
            }
        }
    }

    private var pageTitle: some View {
        Text("Your quotes")
            .font(.robotoSlab(30, relativeTo: .title))
            .foregroundStyle(Color(.mainText))
            .id(HomeTimelineMetrics.topAnchor)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 10, trailing: 20))
    }

    private func sectionTitle(_ title: String,
                              surface: HomeTimelineSection.Surface) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .listRowBackground(surface.color(for: colorScheme))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 12, leading: 20, bottom: 0, trailing: 20))
    }

    private var upcomingVisitsEmptyCard: some View {
        HStack(spacing: 12) {
            Image("VisitsEmpty")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color(.statusMutedText))
                .frame(width: 42, height: 42)
                .background(Color(.fieldFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("No upcoming visits yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                Text("Book a visit and it will appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(visitCardFill, in: HomeTimelineMetrics.visitCardShape)
        .clipShape(HomeTimelineMetrics.visitCardShape)
        .overlay(HomeTimelineMetrics.visitCardShape.strokeBorder(Color(.separator), lineWidth: 0.5))
        .listRowBackground(HomeTimelineSection.Surface.warm.color(for: colorScheme))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 20, trailing: 20))
    }

    private func quoteTimelineRow(_ quote: QuoteSummary,
                                  surface: HomeTimelineSection.Surface) -> some View {
        ZStack {
            QuoteRow(quote: quote, unpricedCount: unpricedCount(quote))
            NavigationLink(value: quote) { EmptyView() }
                .opacity(0)
        }
        .listRowBackground(surface.color(for: colorScheme))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 5, trailing: 20))
        .onAppear { onPrefetchQuote(quote) }
        .contextMenu { quoteMenu(quote) }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { onDeleteQuote(quote) } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private func visitRow(_ visit: ScheduledVisit,
                          surface: HomeTimelineSection.Surface,
                          bottomInset: CGFloat) -> some View {
        let presentation = visitPresentation(visit)

        return Button { onSelectVisit(visit) } label: {
            HStack(spacing: 12) {
                Image("VisitsEmpty")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(Color(.mainText).opacity(0.72))
                    .frame(width: 42, height: 42)
                    .background(Color(.fieldFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(visit.title)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Text(visit.timeRangeText)
                        .font(.caption2)
                        .foregroundStyle(presentation.status.color)
                        .lineLimit(1)
                    if let detail = presentation.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(visitCardFill, in: HomeTimelineMetrics.visitCardShape)
            .clipShape(HomeTimelineMetrics.visitCardShape)
            .overlay(HomeTimelineMetrics.visitCardShape.strokeBorder(Color(.separator), lineWidth: 0.5))
            .contentShape(.contextMenuPreview, HomeTimelineMetrics.visitCardShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(visit.accessibilityText). \(presentation.status.accessibilityLabel). Record a quote")
        .listRowBackground(surface.color(for: colorScheme))
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: bottomInset, trailing: 20))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { onDeleteVisit(visit) } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private var visitCardFill: Color {
        colorScheme == .dark
            ? Color(red: 28 / 255, green: 28 / 255, blue: 30 / 255)
            : Color(.cardSurface)
    }
}
