//
//  ClientsDestinations.swift
//  Verbal
//
//  Where a tap goes on the Clients tab, declared once on the tab's root.
//

import SwiftUI

/// Where a tapped client and a tapped quote go, for the Clients tab.
///
/// Both declared together, once, on the tab's root — and both pushed by value.
/// That pairing is the point: a screen pushed by a *closure* link is not built
/// by the stack, so the stack's destinations are out of scope inside it, and
/// the thread at the foot of a client's page had nowhere to push to. Declaring
/// a second copy on that page instead made one tap push twice. Pushing the
/// client by value too puts its page inside the stack, where the quote
/// destination below reaches it.
///
/// Rows are read from the session rather than taken from the pushed value,
/// which is a snapshot of whatever the list held when it was tapped.
struct ClientsDestinations: ViewModifier {
    @Environment(SessionStore.self) private var session

    func body(content: Content) -> some View {
        content
            .navigationDestination(for: ClientKey.self) { key in
                ClientDetailView(key: key)
            }
            .navigationDestination(for: QuoteSummary.self) { quote in
                QuoteDetailView(
                    quote: session.quotes.first { $0.id == quote.id } ?? quote,
                    initialLineItems: session.lineItems(for: quote.id) ?? [],
                    onDeleted: {}
                )
            }
    }
}
