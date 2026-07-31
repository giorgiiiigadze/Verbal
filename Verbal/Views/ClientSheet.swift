//
//  ClientSheet.swift
//  Verbal
//
//  Names the client a quote is for. Offers people the user has quoted before,
//  so repeat customers are one tap instead of retyping.
//

import SwiftUI

struct ClientSheet: View {
    @Binding var name: String

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var recent: [String] = []
    @FocusState private var fieldFocused: Bool

    /// Previously-used names narrowed by what's been typed so far.
    private var suggestions: [String] {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = query.isEmpty
            ? recent
            : recent.filter { $0.lowercased().contains(query) && $0.lowercased() != query }
        return Array(matches.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Who's it for?")
                    .font(.robotoSlab(22, relativeTo: .title2))
                    .foregroundStyle(Color(.mainText))
                Spacer()
                Button(role: .close) { dismiss() }
            }

            Text("Their name goes at the top of the quote you send.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("e.g. Sarah Chen", text: $draft)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Color(.mainText))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($fieldFocused)
                .onSubmit(commit)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.cardSurface), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )

            if !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    draft = suggestion
                                    commit()
                                } label: {
                                    Text(suggestion)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color(.blueAccentText))
                                        .lineLimit(1)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(Color(.royalBlue25), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollClipDisabled()
                }
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            Button(action: commit) {
                Text("Save")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(.royalBlue600), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: suggestions)
        .presentationDetents([.height(360)])
        .presentationCornerRadius(28)
        .presentationBackground(Color(.surface))
        .task {
            draft = name
            recent = (try? await QuoteService.customerNames()) ?? []
            // Land with the keyboard up — the field is the only thing to do here.
            try? await Task.sleep(for: .seconds(0.35))
            fieldFocused = true
        }
    }

    private func commit() {
        name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }
}
