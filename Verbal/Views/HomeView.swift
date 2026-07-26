//
//  HomeView.swift
//  Verbal
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var showCreate = false
    @State private var quotes: [QuoteSummary] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if quotes.isEmpty {
                    emptyState
                } else {
                    quotesList
                }
            }
            .background(Color(.homeBackground))
            .navigationTitle("Your quotes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        // TODO: second action (define what this button does)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                    }
                    NavigationLink {
                        ProfileView()
                    } label: {
                        AvatarView(image: session.avatarImage, urlString: session.profile?.avatarUrl, size: 30)
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
                QuoteRecordingView()
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    // MARK: - List

    private var quotesList: some View {
        List {
            ForEach(sections, id: \.title) { section in
                Section {
                    ForEach(section.quotes) { quote in
                        NavigationLink {
                            QuoteDetailView(quote: quote)
                        } label: {
                            QuoteRow(quote: quote)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text(section.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Your quotes appear here..")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            quotes = try await QuoteService.fetchQuotes()
        } catch {
            // Keep whatever we had; a toast/list-error can be added later.
        }
    }

    private var sections: [(title: String, quotes: [QuoteSummary])] {
        let calendar = Calendar.current
        var today: [QuoteSummary] = []
        var week: [QuoteSummary] = []
        var earlier: [QuoteSummary] = []
        for quote in quotes {
            if calendar.isDateInToday(quote.createdAt) {
                today.append(quote)
            } else if calendar.isDate(quote.createdAt, equalTo: Date(), toGranularity: .weekOfYear) {
                week.append(quote)
            } else {
                earlier.append(quote)
            }
        }
        var result: [(String, [QuoteSummary])] = []
        if !today.isEmpty { result.append(("Today", today)) }
        if !week.isEmpty { result.append(("This week", week)) }
        if !earlier.isEmpty { result.append(("Earlier", earlier)) }
        return result
    }
}

private struct QuoteRow: View {
    let quote: QuoteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(quote.displayTitle)
                .font(.headline)
                .foregroundStyle(Color(.mainText))
                .lineLimit(1)
            Text(quote.createdAt, format: .relative(presentation: .named))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }
}

/// Placeholder detail — to be built out into the quote review/edit screen.
private struct QuoteDetailView: View {
    let quote: QuoteSummary

    var body: some View {
        List {
            Section("Summary") {
                Text(quote.jobSummary ?? "—")
            }
            Section("Total") {
                Text(quote.total, format: .number.precision(.fractionLength(2)))
            }
        }
        .navigationTitle(quote.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
