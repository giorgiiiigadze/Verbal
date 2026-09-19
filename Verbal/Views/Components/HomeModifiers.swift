//
//  HomeModifiers.swift
//  Verbal
//
//  View modifiers factored out of Home: the two visit confirmations, the
//  conditional search field, and the two sync watchers. The last three exist
//  as modifiers because Home's body is already at the type-checker's limit.
//

import SwiftUI

// MARK: - Visit Deletion

struct VisitDeleteConfirmation: ViewModifier {
    @Binding var visit: ScheduledVisit?
    let onDelete: (ScheduledVisit) -> Void

    func body(content: Content) -> some View {
        content.alert("Delete upcoming quote?", isPresented: Binding(
            get: { visit != nil },
            set: { if !$0 { visit = nil } }
        ), presenting: visit) { visit in
            Button("Delete", role: .destructive) {
                onDelete(visit)
                self.visit = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: { visit in
            Text("This removes “\(visit.title)” from Upcoming. This can't be undone.")
        }
    }
}

// MARK: - Search

/// Adds `.searchable` only once search has been asked for, and takes it away
/// again when it's dismissed.
///
/// `.searchable` with an `isPresented` binding still reserves the field's place
/// in the navigation bar while it's closed, which is a search bar sitting on a
/// screen nobody asked to search. Attaching the modifier itself conditionally
/// is what actually leaves the screen alone until the magnifier is tapped.
struct SearchWhenAsked: ViewModifier {
    let isActive: Bool
    @Binding var text: String
    @Binding var isPresented: Bool
    let prompt: String

    func body(content: Content) -> some View {
        if isActive {
            content.searchable(text: $text, isPresented: $isPresented, prompt: prompt)
        } else {
            content
        }
    }
}

// MARK: - Filtering

/// Visits arriving from the server, and the moment there is signal to fetch
/// them with.
///
/// A modifier for the same reason `SessionSync` below is one, and not an
/// optional one: two more `onChange`s in that body's chain put the type-checker
/// over its limit outright.
struct VisitSync: ViewModifier {
    let visits: [ScheduledVisit]
    let isOnline: Bool
    let apply: ([ScheduledVisit]) -> Void
    let reconnected: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: visits) { _, fresh in apply(fresh) }
            // Back in signal after a basement: whatever was booked or cancelled
            // down there goes up now, without waiting for a relaunch.
            .onChange(of: isOnline) { _, online in if online { reconnected() } }
    }
}

/// Watches the session's copy of the quote list on Home's behalf.
///
/// A modifier rather than two `onChange`s in the body: that body is already at
/// the limit of what the type-checker will take in one expression, and the
/// second one tipped it over.
struct SessionSync: ViewModifier {
    let quotes: [QuoteSummary]
    let listsLoaded: Bool
    let apply: ([QuoteSummary], Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: quotes) { _, fresh in apply(fresh, listsLoaded) }
            .onChange(of: listsLoaded) { _, loaded in apply(quotes, loaded) }
    }
}
