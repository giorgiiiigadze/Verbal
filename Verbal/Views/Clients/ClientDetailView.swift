//
//  ClientDetailView.swift
//  Verbal
//
//  One client: what they're worth, and everything you've quoted them.
//
//  The contact fields on `customers` — phone, email, address, notes — are
//  written by nothing today, so there is nothing here to show yet. Making them
//  editable is the next step and the reason the table is worth having; this
//  screen is the place they'll go.
//

import SwiftUI

struct ClientDetailView: View {
    let client: Client

    @Environment(SessionStore.self) private var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quotes")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(.mainText))

                    VStack(spacing: 10) {
                        ForEach(client.quotes) { quote in
                            ZStack {
                                QuoteRow(quote: quote,
                                         unpricedCount: unpricedCount(for: quote))
                                // Zero-opacity link, the same trick Home uses to
                                // navigate a row without the default chevron
                                // landing on top of the row's own layout.
                                NavigationLink {
                                    QuoteDetailView(
                                        quote: quote,
                                        initialLineItems: session.lineItems(for: quote.id) ?? [],
                                        onDeleted: {}
                                    )
                                } label: { EmptyView() }
                                .opacity(0)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(.homeBackground))
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Read from the prefetched line items, the same as Home does — the summary
    /// row can't see inside a quote on its own.
    private func unpricedCount(for quote: QuoteSummary) -> Int {
        (session.lineItems(for: quote.id) ?? []).filter(\.isMissingPrice).count
    }

    /// What they're worth and how long they've been a customer. The total is
    /// stated only when one currency covers all of it — see `Client`.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(client.name)
                .font(.robotoSlab(28, relativeTo: .title))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            Text(client.subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let total = client.singleCurrencyTotal {
                Text("\(total) quoted in total")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
