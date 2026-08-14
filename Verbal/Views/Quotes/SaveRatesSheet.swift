//
//  SaveRatesSheet.swift
//  Verbal
//
//  Offered from the review screen when the extraction came back with items it
//  had no price for.
//
//  A "Needs price" line means the speaker never said a number and the rate card
//  had no match. Filling it in on the quote fixes today; saving it to the rate
//  card fixes every time after, because the extraction is given those rates and
//  prices from them directly. This is the one moment the user is looking at the
//  exact list of prices Verbal was missing, so it's the cheapest time to ask.
//

import SwiftUI
import UIKit

/// A line the extraction couldn't price, as a candidate rate-card entry.
struct UnpricedItem: Identifiable {
    let id: UUID
    let name: String
    let unit: String?
    let type: String
}

struct SaveRatesSheet: View {
    let items: [UnpricedItem]
    /// The currency prices are being entered in, for the field prefix.
    let currency: String
    /// The prices that were typed, keyed by line id, and how many reached the
    /// rate card. The two differ when a write fails: the number was still meant
    /// for this quote, so it is applied either way.
    var onSaved: (_ prices: [UUID: Double], _ savedToRateCard: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Typed price per item id. Blank means "not this one".
    @State private var prices: [UUID: String] = [:]
    @State private var isSaving = false
    @FocusState private var focusedItem: UUID?
    /// The rate card as it stands, loaded on appear so each row can say which
    /// saved rate it would rewrite rather than doing it out of sight.
    @State private var existing: [RateCardItem] = []

    /// The saved rate this line would rewrite, if any.
    private func match(for item: UnpricedItem) -> RateCardItem? {
        existing.first { $0.looksLike(item.name) }
    }

    private var currencySymbol: String {
        AppCurrency(rawValue: currency)?.symbol ?? currency
    }

    /// Only rows with a usable number get saved — the rest are left alone
    /// rather than written as a rate with no price, which is what the rate card
    /// exists to avoid.
    private var priced: [(item: UnpricedItem, price: Double)] {
        items.compactMap { item in
            guard let text = prices[item.id]?.replacingOccurrences(of: ",", with: "."),
                  let value = Double(text.trimmingCharacters(in: .whitespaces)),
                  value > 0 else { return nil }
            return (item, value)
        }
    }

    /// Sized to the list rather than fixed: two rates shouldn't open a sheet
    /// with a void under them, and eight shouldn't need scrolling to reach the
    /// button.
    private var detentHeight: CGFloat {
        let visibleRows = CGFloat(min(items.count, 6))
        return min(232 + visibleRows * 56, 660)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Verbal fills them in automatically next time you quote the same work. Leave any blank to skip it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)

                // One bordered table with hairline rules, matching how line items
                // are drawn on the quote itself — rather than a card per row, each
                // holding another boxed field.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            row(item)
                            if index != items.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
                }
                .scrollBounceBehavior(.basedOnSize)
                .padding(.top, 18)
            }
            .padding(.horizontal, 24)
            .background(Color(.systemBackground))
            .navigationTitle("Save these prices?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { hideKeyboard() }.fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                // A single action. The close control in the header is the way out,
                // so a second "Not now" underneath would only add weight.
                Button {
                    save()
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else {
                            Text(priced.isEmpty
                                 ? "Add a price to save"
                                 : "Save \(priced.count) rate\(priced.count == 1 ? "" : "s")")
                                .font(.headline)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(priced.isEmpty
                                ? Color(.royalBlue600).opacity(0.4)
                                : Color(.royalBlue600),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(priced.isEmpty || isSaving)
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .background(Color(.systemBackground))
            }
        }
        .presentationDetents([.height(detentHeight), .large])
        .presentationBackground(Color(.systemBackground))
    }

    private func row(_ item: UnpricedItem) -> some View {
        let isFilled = !(prices[item.id] ?? "").isEmpty
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(2)
                if let unit = item.unit, !unit.isEmpty {
                    Text("per \(unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Naming it matters: the comparison is loose enough to pair
                // "Replacement toilet" with "Toilet Installation", and rewriting
                // the wrong saved price without showing which would be worse
                // than the duplicate it prevents.
                if let match = match(for: item) {
                    Text("Updates “\(match.name)”")
                        .font(.caption2)
                        .foregroundStyle(Color(.blueAccentText))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            // Drawn like an amount on the quote rather than a boxed input: the
            // number is the thing, and a field border around every row turned
            // the list into a stack of containers.
            HStack(spacing: 2) {
                Text(currencySymbol)
                TextField("0", text: Binding(
                    get: { prices[item.id] ?? "" },
                    set: { prices[item.id] = $0 }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedItem, equals: item.id)
                .frame(width: 58)
            }
            .font(.callout.weight(.semibold).monospacedDigit())
            // Matches the placeholder while empty — a coloured symbol beside a
            // grey zero reads as one of them being wrong.
            .foregroundStyle(isFilled ? Color(.mainText) : Color.secondary)
        }
        .padding(.vertical, 14)
        // The number is a small target; the whole row reaches it.
        .contentShape(Rectangle())
        .onTapGesture { focusedItem = item.id }
    }

    private func save() {
        isSaving = true
        Task {
            // Repricing an existing rate beats adding a second one for the same
            // job: the card is handed to the extraction whole, and duplicates
            // would have it choosing between two prices and never saying which.
            var saved = 0

            for entry in priced {
                let match = match(for: entry.item)
                do {
                    if let match {
                        try await QuoteService.updateRateCardPrice(id: match.id, unitPrice: entry.price)
                    } else {
                        try await QuoteService.addRateCardItem(
                            name: entry.item.name,
                            unit: entry.item.unit,
                            unitPrice: entry.price,
                            type: entry.item.type
                        )
                    }
                    saved += 1
                } catch {
                    // One failure shouldn't discard the rest; the rate card has
                    // no ordering or totals to keep consistent, so a partial
                    // save is simply fewer rates, not a broken one.
                    continue
                }
            }

            isSaving = false
            onSaved(Dictionary(uniqueKeysWithValues: priced.map { ($0.item.id, $0.price) }), saved)
            dismiss()
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
