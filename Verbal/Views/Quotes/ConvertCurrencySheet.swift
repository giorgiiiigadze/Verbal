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
    /// The quote's stored total, which includes tax.
    let currentTotal: Double
    /// The quote's tax percentage, so the preview compares a tax-inclusive
    /// figure with a tax-inclusive one rather than with a bare subtotal.
    let taxRate: Double
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

    /// Preview subtotal after conversion (sum of rounded line totals, pre-tax).
    private var newSubtotal: Double? {
        guard let rate else { return nil }
        return lineItems.reduce(0.0) { sum, item in
            guard let quantity = item.quantity, let unitPrice = item.unitPrice else { return sum }
            return sum + quantity * convertedUnit(unitPrice, rate)
        }
    }

    /// The converted subtotal grossed up by tax — what the quote will actually
    /// total once saved, and so the only figure worth putting next to "Now".
    private var newTotal: Double? { newSubtotal.map(withTax) }

    /// Mirrors the database's arithmetic on a subtotal.
    private func withTax(_ subtotal: Double) -> Double {
        let tax = (subtotal * taxRate / 100).roundedToCents
        return (subtotal + tax).roundedToCents
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
            .background(Color(.systemBackground))
            .navigationTitle("Change currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }.disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Color(.systemBackground))
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

    /// Convert every priced line item and relabel the quote, restoring any price
    /// already written if a later write fails. A half-converted quote mixes two
    /// currencies on the document the customer receives, with nothing on screen
    /// to say so — leaving it untouched is the only safe way to fail.
    private func applyConversion(rate: Double, subtotal: Double) async throws {
        var written: [(id: UUID, unitPrice: Double)] = []
        do {
            for item in lineItems {
                guard let unitPrice = item.unitPrice else { continue }
                try await QuoteService.updateLineItemPrice(
                    id: item.id, unitPrice: convertedUnit(unitPrice, rate))
                written.append((item.id, unitPrice))
            }
            try await QuoteService.updateCurrencyAndSubtotal(
                id: quoteID, currency: toCode, subtotal: subtotal)
        } catch {
            for original in written.reversed() {
                try? await QuoteService.updateLineItemPrice(
                    id: original.id, unitPrice: original.unitPrice)
            }
            throw error
        }
    }

    private func save(convert: Bool) {
        isSaving = true
        Task {
            do {
                if convert, let rate, let subtotal = newSubtotal {
                    try await applyConversion(rate: rate, subtotal: subtotal)
                    onDone(toCode, withTax(subtotal))
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
