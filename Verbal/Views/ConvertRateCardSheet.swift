//
//  ConvertRateCardSheet.swift
//  Verbal
//
//  Shown when the user changes their main currency while they have saved rates.
//
//  Rate card items store a bare number and no currency of their own, so the
//  main-currency setting is the only thing deciding whether "50" reads as $50 or
//  £50. Switching it without asking silently redenominates every saved price —
//  and those prices are what the AI reaches for when it fills in a quote. So the
//  same choice quotes already get is offered here: reprice at today's rate, or
//  relabel and keep the numbers.
//

import SwiftUI

struct ConvertRateCardSheet: View {
    /// The saved rates that actually carry a price; the rest need no decision.
    let items: [RateCardItem]
    let fromCode: String
    let toCode: String
    /// Called once the change is safe to apply. `converted` reports whether the
    /// stored prices were rewritten or merely relabelled.
    var onDone: (_ converted: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rate: Double?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isSaving = false

    /// Rates keep their pence: a saved price can be small enough that rounding
    /// to whole units (as quote totals do) would distort it.
    private func convertedPrice(_ price: Double, _ rate: Double) -> Double {
        (price * rate).roundedToCents
    }

    private var countLabel: String {
        "\(items.count) saved rate\(items.count == 1 ? "" : "s")"
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

                Text("You have \(countLabel) priced in \(fromCode).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if isLoading {
                    ProgressView("Fetching today's rate…")
                        .padding(.vertical, 12)
                } else if let rate {
                    VStack(spacing: 14) {
                        Text("Today's rate: 1 \(fromCode) = \(rate.formatted(.number.precision(.fractionLength(0...4)))) \(toCode)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        // A worked example beats an abstract promise — the user
                        // can see what happens to a price they recognize.
                        if let example = items.first, let price = example.unitPrice {
                            VStack(spacing: 8) {
                                Text(example.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                HStack(spacing: 12) {
                                    amountBox(title: "Now", value: price, code: fromCode)
                                    Image(systemName: "arrow.right")
                                        .foregroundStyle(.secondary)
                                    amountBox(title: "Converted",
                                              value: convertedPrice(price, rate),
                                              code: toCode)
                                }
                            }
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
                            Text("Convert \(countLabel)")
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

    /// Reprice every saved rate, putting back the ones already written if a
    /// later one fails. A half-converted rate card is worse than an unconverted
    /// one: the prices look right individually but no longer share a currency,
    /// and the AI would quote from the mix without knowing.
    private func applyConversion(rate: Double) async throws {
        var written: [(id: UUID, unitPrice: Double)] = []
        do {
            for item in items {
                guard let price = item.unitPrice else { continue }
                try await QuoteService.updateRateCardPrice(
                    id: item.id, unitPrice: convertedPrice(price, rate))
                written.append((item.id, price))
            }
        } catch {
            for original in written.reversed() {
                try? await QuoteService.updateRateCardPrice(
                    id: original.id, unitPrice: original.unitPrice)
            }
            throw error
        }
    }

    private func save(convert: Bool) {
        isSaving = true
        Task {
            do {
                if convert, let rate {
                    try await applyConversion(rate: rate)
                }
                // Only switch the setting once the prices underneath it are
                // known to match; otherwise the label and the numbers disagree.
                onDone(convert)
                dismiss()
            } catch {
                loadError = error.localizedDescription
                isSaving = false
            }
        }
    }
}
