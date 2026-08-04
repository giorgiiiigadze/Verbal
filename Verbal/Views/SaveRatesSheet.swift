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

    var body: some View {
        ScrollView {
                VStack(spacing: 0) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(Color(.blueAccentText))
                        .frame(height: 46)

                    Text("Remember these prices?")
                        .font(.robotoSlab(24, relativeTo: .title2))
                        .foregroundStyle(Color(.mainText))
                        .multilineTextAlignment(.center)
                        .padding(.top, 14)

                    Text("Saved rates get filled in automatically next time you quote the same work. Leave any blank to skip it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                    .padding(.top, 22)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }
        .scrollBounceBehavior(.basedOnSize)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }.fontWeight(.semibold)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
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
                    .frame(height: 54)
                    .background(priced.isEmpty
                                ? Color(.royalBlue600).opacity(0.4)
                                : Color(.royalBlue600),
                                in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(priced.isEmpty || isSaving)

                Button("Not now") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(.surface))
        }
        // Full height: the list of prices is the point, and a medium detent
        // hides all but the first row behind the save button.
        .presentationDetents([.large])
        .presentationCornerRadius(28)
        .presentationBackground(Color(.surface))
    }

    private func row(_ item: UnpricedItem) -> some View {
        HStack(spacing: 12) {
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
            }
            Spacer(minLength: 8)
            // Symbol and number share one enclosure, so they read as a single
            // field rather than a stray glyph beside a right-aligned number.
            HStack(spacing: 3) {
                Text(currencySymbol).foregroundStyle(.secondary)
                TextField("0", text: Binding(
                    get: { prices[item.id] ?? "" },
                    set: { prices[item.id] = $0 }
                ))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            }
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.surface), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.cardSurface), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private func save() {
        isSaving = true
        Task {
            // Repricing an existing rate beats adding a second one under the
            // same name: the rate card is handed to the extraction whole, and
            // duplicates would have it choosing between two prices for one job.
            let existing = (try? await QuoteService.fetchRateCard()) ?? []
            var saved = 0

            for entry in priced {
                let match = existing.first {
                    $0.name.compare(entry.item.name, options: .caseInsensitive) == .orderedSame
                }
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
