//
//  EditQuoteView.swift
//  Verbal
//
//  Edit the words of a saved quote: job summary and scope of work.
//
//  Renaming lives in the quote's own menu, and the priced lines in a sheet
//  opened from the card that shows them. What's left here is the prose.
//

import SwiftUI

struct EditQuoteView: View {
    let quoteId: UUID
    /// Called after a successful save with the new job summary and scope, so
    /// the detail screen can reflect the edits without a full refetch.
    var onSaved: (_ jobSummary: String, _ scope: [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Carried through untouched. Renaming lives in the detail screen's menu,
    /// behind a native alert; this screen still has to write the title back,
    /// because saving rewrites the whole row and a title left out is a title
    /// erased.
    private let title: String
    @State private var jobSummary: String
    /// Scope edited as one row per bullet, the way the priced lines are edited;
    /// rows left blank are dropped on save.
    @State private var scope: [ScopeLine]
    @FocusState private var focusedLine: UUID?
    @State private var isSaving = false
    /// Set when a write failed, so the sheet reports it instead of closing on
    /// edits that were never stored.
    @State private var saveError = false

    init(quoteId: UUID,
         title: String,
         jobSummary: String,
         scope: [String],
         onSaved: @escaping (String, [String]) -> Void) {
        self.quoteId = quoteId
        self.onSaved = onSaved
        self.title = title
        _jobSummary = State(initialValue: jobSummary)
        // Built with an explicit loop (not `.map`) so the value-type initializer
        // isn't called from a nonisolated map closure under main-actor isolation.
        var built: [ScopeLine] = []
        for item in scope { built.append(ScopeLine(text: item)) }
        _scope = State(initialValue: built)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Job summary", text: $jobSummary, axis: .vertical)
                        .lineLimit(2...5)
                }
                .listRowBackground(Color(.cardSurface))

                Section {
                    ForEach($scope) { $line in
                        TextField("New item", text: $line.text, axis: .vertical)
                            .lineLimit(1...4)
                            .focused($focusedLine, equals: line.id)
                    }
                    .onDelete { scope.remove(atOffsets: $0) }

                    Button {
                        // Focusing the new row is what makes a list of one-line
                        // fields quick to fill: add, type, add again.
                        let line = ScopeLine(text: "")
                        scope.append(line)
                        focusedLine = line.id
                    } label: {
                        Label("Add item", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Scope of work")
                } footer: {
                    Text("Swipe a line to remove it.")
                }
                .listRowBackground(Color(.cardSurface))

            }
            .scrollContentBackground(.hidden)
            .background(Color(.homeBackground))
            .navigationTitle("Edit quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await save() } }
                            .fontWeight(.semibold)
                    }
                }
            }
            .alert("Couldn't save your changes", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Check your connection and tap Save again. Your edits are still here.")
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSummary = jobSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let newScope = scope
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        do {
            try await QuoteService.updateQuoteText(
                id: quoteId,
                title: newTitle.isEmpty ? nil : newTitle,
                jobSummary: newSummary.isEmpty ? nil : newSummary,
                scope: newScope
            )
        } catch {
            // Staying open on a failed write is the point: closing with a
            // success haptic would tell the user their prices were saved when
            // they weren't, and they'd find out days later.
            saveError = true
            return
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onSaved(newSummary, newScope)
        dismiss()
    }
}

/// One editable bullet. Identity is the view-local id, not the text, so a row
/// keeps focus while it's being typed into.
private struct ScopeLine: Identifiable {
    let id = UUID()
    var text: String
}
