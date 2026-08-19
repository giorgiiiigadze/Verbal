//
//  ReadyToAddSheet.swift
//  Verbal
//
//  The rate card's other half: rates the user has already priced out loud,
//  waiting to be kept.
//

import SwiftUI
import UIKit

/// The prices already spoken into quotes, offered back as rates to keep.
///
/// Everything arrives selected. These are prices the user chose once already, so
/// the question is which to leave out, not which to take — and the sheet is only
/// worth opening if saying yes to all of it is one tap.
struct ReadyToAddSheet: View {
    let candidates: [RateCandidate]
    var onAdded: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var skipped: Set<UUID> = []
    @State private var isSaving = false

    /// `royalBlue600` defines a light appearance only, so in dark mode it stays
    /// a near-black navy and a filled circle of it disappears into the card it
    /// sits on. The mic tab makes the same swap for the same reason.
    private var checkTint: Color {
        colorScheme == .dark ? .white : Color(.royalBlue600)
    }

    private var chosen: [RateCandidate] {
        candidates.filter { !skipped.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(candidates) { candidate in
                        row(candidate)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .scrollBounceBehavior(.always)
            .navigationTitle("Ready to add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button { save() } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(chosen.isEmpty
                                 ? "Nothing selected"
                                 : "Save \(chosen.count) rate\(chosen.count == 1 ? "" : "s")")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(chosen.isEmpty
                                ? Color(.royalBlue600).opacity(0.4)
                                : Color(.royalBlue600),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(chosen.isEmpty || isSaving)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground))
        .presentationDetents([.height(detentHeight), .large])
        .presentationBackground(Color(.systemBackground))
    }

    /// Sized to the list, like the sheet that offers unpriced lines: three
    /// candidates shouldn't open onto a void, twelve shouldn't hide the button.
    private var detentHeight: CGFloat {
        let visible = CGFloat(min(candidates.count, 6))
        return min(220 + visible * 62, 660)
    }

    private func row(_ candidate: RateCandidate) -> some View {
        let isChosen = !skipped.contains(candidate.id)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.18)) {
                if isChosen { skipped.insert(candidate.id) } else { skipped.remove(candidate.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? checkTint : Color(.separator))
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Text(Self.label(for: candidate.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(AppCurrency.format(candidate.unitPrice))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color(.mainText))
                    if let unit = candidate.unit, !unit.isEmpty {
                        Text("per \(unit)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            // Tinted, not white. This sheet's page is white, so a white row
            // was a hairline outline around nothing.
            .background(Color(.fieldFill),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
            .opacity(isChosen ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    private static func label(for type: String) -> String {
        switch type {
        case "labor": return "Labor"
        case "material": return "Material"
        default: return type.capitalized
        }
    }

    private func save() {
        isSaving = true
        Task {
            var saved = 0
            for candidate in chosen {
                do {
                    try await QuoteService.addRateCardItem(
                        name: candidate.name, unit: candidate.unit,
                        unitPrice: candidate.unitPrice, type: candidate.type)
                    saved += 1
                } catch {
                    // Keep going: one failed write shouldn't cost the others,
                    // and the count reported is the count that landed.
                    continue
                }
            }
            isSaving = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAdded(saved)
            dismiss()
        }
    }
}
