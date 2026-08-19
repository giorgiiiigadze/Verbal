//
//  AddRateItemView.swift
//  Verbal
//
//  The sheet the rate card is filled in through.
//

import SwiftUI
import UIKit

/// New rate, or a correction to one that exists.
///
/// The old version was a Settings-style form: four fields of equal weight, a
/// full-height sheet, and a "Custom…" unit that opened a second field — which is
/// how one card ended up holding both "m²" and "square meters". It also had no
/// idea what was already saved, so the same job could be entered twice at
/// different prices, and the whole card goes to the model on every extraction:
/// two prices for one job means it picks one, and the user never learns which.
///
/// So the warning is the centrepiece. It watches what's being typed and names
/// the rate it collides with, with an offer to correct that one instead.
struct AddRateItemView: View {
    /// What's already saved, so a collision can be spotted while it's typed
    /// rather than discovered months later in a wrong quote.
    let existing: [RateCardItem]
    /// Set when the sheet opened to correct a specific rate.
    var editing: RateCardItem?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = "each"
    @State private var priceText = ""
    @State private var type = "labor"
    @State private var isSaving = false
    /// The rate being corrected — either the one passed in, or one the user
    /// adopted from the duplicate warning.
    @State private var target: RateCardItem?
    @FocusState private var nameFocused: Bool

    private let types = ["labor", "material", "other"]
    private let commonUnits = ["each", "m²", "m", "hour", "day", "job", "litre", "kg"]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var price: Double? {
        let cleaned = priceText.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : Double(cleaned)
    }

    /// A price is required. A rate without one can't price anything — it just
    /// rides along in every extraction request as noise.
    private var canSave: Bool {
        !trimmedName.isEmpty && (price ?? 0) > 0
    }

    /// The saved rate this one looks like, if any. Shares its comparison with
    /// the save-from-quote sheet, so both doors into the rate card agree on
    /// what counts as the same job.
    private var collision: RateCardItem? {
        guard target == nil, trimmedName.count >= 3 else { return nil }
        return existing.first { $0.id != editing?.id && $0.looksLike(trimmedName) }
    }

    var body: some View {
        NavigationStack {
            // The inset moved off the sheet and onto each piece inside it, so
            // this scroll view spans the full width. It is what clips the unit
            // chips, and inset by 24 it cut them off short of the edge.
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    field("What is it? (e.g. Re-tiling)", text: $name)
                        .focused($nameFocused)
                        .textInputAutocapitalization(.sentences)

                    if let collision { duplicateWarning(collision) }

                    HStack(spacing: 4) {
                        Text(AppCurrency.current.symbol).foregroundStyle(.secondary)
                        TextField("0", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                    .font(.body.monospacedDigit())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.fieldFill),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )

                    // Type and unit are the same question asked twice — pick one
                    // of a short list — so they're asked the same way. This was
                    // a segmented control sitting a line above the unit chips:
                    // the only stock iOS control in a sheet drawn by hand, and
                    // a second idiom for a choice the row below already had one
                    // for. It also truncated "Material" to "Mater…" at larger
                    // text sizes, which a chip that can scroll never does.
                    chipRow("Type", options: types,
                            display: { $0.capitalized }, selection: $type)

                    // Tappable rather than a picker with a "Custom…" escape
                    // hatch: the two-step is what let the same unit be typed
                    // two different ways.
                    chipRow("Per", options: unitOptions, selection: $unit)
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemBackground))
            .navigationTitle(target == nil ? "New rate" : "Edit rate")
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
                            Text(target == nil ? "Save rate" : "Update rate").font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(canSave ? Color(.royalBlue600) : Color(.royalBlue600).opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave || isSaving)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Color(.systemBackground))
            }
        }
        // The chip row stands ~28pt taller than the segmented control it
        // replaced — a caption above it, and a taller target under the thumb.
        .presentationDetents([.height(560)])
        .presentationBackground(Color(.systemBackground))
        .task {
            if let editing { adopt(editing) }
            try? await Task.sleep(for: .seconds(0.35))
            nameFocused = true
        }
    }

    /// Always offers the current unit, so a rate saved with something unusual
    /// doesn't lose it just by being opened.
    private var unitOptions: [String] {
        commonUnits.contains(unit) ? commonUnits : [unit] + commonUnits
    }

    /// A labelled row of chips — the sheet's one way of choosing from a short
    /// list, so type and unit stop being two controls for the same job.
    ///
    /// Always scrollable, even where the options fit today: at accessibility
    /// text sizes three chips stop fitting on a line, and scrolling past them is
    /// better than a row that clips or wraps.
    private func chipRow(_ label: String,
                         options: [String],
                         display: @escaping (String) -> String = { $0 },
                         selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            // Runs edge to edge, like the chips on a quote. The row steps back
            // out of the content inset and puts it back on the chips
            // themselves, so they start in line with the fields above but keep
            // scrolling to the sheet's own edges — the last chip no longer sits
            // against an invisible wall with clear space beyond it.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(options, id: \.self) { option in
                        chip(display(option),
                             isSelected: selection.wrappedValue == option) {
                            selection.wrappedValue = option
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -24)
        }
    }

    private func chip(_ title: String,
                      isSelected: Bool,
                      select: @escaping () -> Void) -> some View {
        Button {
            // A segmented control ticks under the thumb on every change. Losing
            // that was the one thing the stock picker did better, so it comes
            // back explicitly — and the fill moves rather than cutting.
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.18)) { select() }
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isSelected ? .white : Color(.mainText))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? Color(.royalBlue600) : Color(.fieldFill),
                            in: Capsule())
                .overlay(
                    Capsule().strokeBorder(isSelected ? .clear : Color(.separator),
                                           lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func duplicateWarning(_ item: RateCardItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(LineItemRow.amber)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 6) {
                Text("You already have “\(item.name)”\(item.priceText.map { " at \($0)" } ?? "")")
                    .font(.footnote)
                    .foregroundStyle(Color(.mainText))
                    .fixedSize(horizontal: false, vertical: true)
                Button("Correct that one instead") { adopt(item) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.blueAccentText))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(LineItemRow.amber.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Load an existing rate into the form and switch to correcting it.
    private func adopt(_ item: RateCardItem) {
        target = item
        name = item.name
        unit = item.unit ?? "each"
        type = item.type
        priceText = item.unitPrice.map {
            $0 == $0.rounded() ? String(Int($0)) : String($0)
        } ?? ""
    }

    private func save() {
        isSaving = true
        Task {
            if let target {
                try? await QuoteService.updateRateCardItem(
                    id: target.id, name: trimmedName, unit: unit,
                    unitPrice: price, type: type)
            } else {
                try? await QuoteService.addRateCardItem(
                    name: trimmedName, unit: unit, unitPrice: price, type: type)
            }
            isSaving = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            dismiss()
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(Color(.mainText))
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.fieldFill),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
    }
}
