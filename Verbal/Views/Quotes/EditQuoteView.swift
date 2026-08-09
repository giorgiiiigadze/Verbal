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
    /// Scope edited as one bullet per line; blank lines are dropped on save.
    @State private var scopeText: String
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
        _scopeText = State(initialValue: scope.joined(separator: "\n"))
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
                    TextField("One item per line", text: $scopeText, axis: .vertical)
                        .lineLimit(3...10)
                } header: {
                    Text("Scope of work")
                } footer: {
                    Text("Each line becomes a bullet on the quote.")
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
        let newScope = scopeText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
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
