//
//  ConvertCurrencySheet.swift
//  Verbal
//
//  Shown when the user changes a saved quote's currency. Offers either a plain
//  relabel (keep the numbers) or an assisted conversion at today's rate, with a
//  preview to confirm before anything is saved. Amounts round to the nearest
//  whole so quotes stay clean.
//

import SwiftUI

struct ConvertCurrencySheet: View {
    let quoteID: UUID
    let lineItems: [QuoteLineItem]
    let currentTotal: Double
    let fromCode: String
    let toCode: String
    /// Called after the change is persisted. `newTotal == nil` means relabel only.
    var onDone: (_ newCurrency: String, _ newTotal: Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rate: Double?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isSaving = false

    private func convertedUnit(_ price: Double, _ rate: Double) -> Double {
        (price * rate).rounded()
    }

    /// Preview total after conversion (sum of rounded line totals).
    private var newTotal: Double? {
        guard let rate else { return nil }
        return lineItems.reduce(0.0) { sum, item in
            guard let quantity = item.quantity, let unitPrice = item.unitPrice else { return sum }
            return sum + quantity * convertedUnit(unitPrice, rate)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 8)

                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)

                Text("Change to \(toCode)?")
                    .font(.title3.bold())
                    .foregroundStyle(Color(.mainText))

                if isLoading {
                    ProgressView("Fetching today's rate…")
                        .padding(.vertical, 12)
                } else if let rate {
                    VStack(spacing: 14) {
                        Text("Today's rate: 1 \(fromCode) = \(rate.formatted(.number.precision(.fractionLength(0...4)))) \(toCode)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            amountBox(title: "Now", value: currentTotal, code: fromCode)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                            amountBox(title: "Converted", value: newTotal ?? currentTotal, code: toCode)
                        }
                    }
                } else if let loadError {
                    Text(loadError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 10) {
                    if rate != nil {
                        Button {
                            save(convert: true)
                        } label: {
                            Text("Convert amounts & save")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Color(.royalBlue600))
                        .controlSize(.large)
                        .disabled(isSaving)
                    }

                    Button {
                        save(convert: false)
                    } label: {
                        Text("Just relabel (keep numbers)")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .disabled(isSaving)
                }
                .padding(.horizontal, 4)
            }
            .padding(24)
            .background(Color(.homeBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            do {
                rate = try await FXService.rate(from: fromCode, to: toCode)
            } catch {
                loadError = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func amountBox(title: String, value: Double, code: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(AppCurrency.format(value, code: code))
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color(.mainText))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.surface), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func save(convert: Bool) {
        isSaving = true
        Task {
            do {
                if convert, let rate {
                    for item in lineItems {
                        if let unitPrice = item.unitPrice {
                            try await QuoteService.updateLineItemPrice(
                                id: item.id, unitPrice: convertedUnit(unitPrice, rate))
                        }
                    }
                    let total = newTotal ?? currentTotal
                    try await QuoteService.updateCurrencyAndTotal(id: quoteID, currency: toCode, total: total)
                    onDone(toCode, total)
                } else {
                    try await QuoteService.updateCurrency(id: quoteID, currency: toCode)
                    onDone(toCode, nil)
                }
                dismiss()
            } catch {
                loadError = error.localizedDescription
                isSaving = false
            }
        }
    }
}
