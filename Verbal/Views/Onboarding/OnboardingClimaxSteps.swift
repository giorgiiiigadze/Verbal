//
//  OnboardingClimaxSteps.swift
//  Verbal
//
//  A preview of the rate card the person has just set up. Recording starts
//  from the signed-in app, where it belongs alongside the normal quote flow.
//

import SwiftUI

struct OnboardingResultStep: View {
    let model: OnboardingModel
    let currencyCode: String

    private struct SampleLine {
        let description: String
        let quantity: Int
        let unit: String
        let price: Double?
    }

    private var title: String {
        model.hasAnyRate
            ? "Your first quote is\nhalf-written already."
            : "This is what a job\nturns into."
    }

    private var spokenLine: String {
        guard let first = model.draftRates.first else {
            return "“Replace the toilet, ninety. Three mixer taps.”"
        }
        return "“\(first.name.lowercased()), and the materials from the supplier — I'll price those tomorrow.”"
    }

    private var lines: [SampleLine] {
        guard !model.draftRates.isEmpty else {
            return [
                .init(description: "Remove old toilet and fit new toilet", quantity: 1, unit: "each", price: 90),
                .init(description: "Mixer taps", quantity: 3, unit: "each", price: nil),
            ]
        }
        var sample = model.draftRates.prefix(2).map {
            SampleLine(description: $0.name, quantity: 1, unit: $0.unit, price: $0.price)
        }
        sample.append(.init(description: "Materials from the supplier", quantity: 1, unit: "job", price: nil))
        return sample
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeading(title: title)

            Text(spokenLine)
                .font(.callout)
                .italic()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingStyle.action.opacity(0.5))
                .frame(maxWidth: .infinity)

            LineItemsCard {
                ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                    if index > 0 { Divider() }
                    LineItemRow(description: line.description,
                                quantityText: "\(line.quantity) \(line.unit)",
                                isMissingPrice: line.price == nil,
                                lineTotal: line.price.map { $0 * Double(line.quantity) },
                                currencyCode: currencyCode)
                }
            }

            Text(model.hasAnyRate
                 ? "Saved to your rate card. Record a job in the app and these fill themselves in."
                 : "Your rate card is a tab away whenever you want to fill it in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

struct OnboardingMilestoneStep: View {
    let model: OnboardingModel

    var body: some View {
        // Echo the earlier time-saved result: this is the second payoff in the
        // flow, so it should read as an outcome rather than another form card.
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Your setup")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(OnboardingStyle.action)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(model.draftRates.count)")
                        .font(.scaledSystem(80, relativeTo: .largeTitle,
                                            weight: .medium, design: .rounded))
                        .tracking(-4)
                        .foregroundStyle(OnboardingStyle.action)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(model.draftRates.count == 1 ? "rate" : "rates")
                        .font(.robotoSlab(28, relativeTo: .title))
                        .foregroundStyle(Color(.mainText))
                }

                Text("ready on your rate card")
                    .font(.callout)
                    .foregroundStyle(Color(.mainText))
            }
            .accessibilityElement(children: .combine)

            Rectangle()
                .fill(Color(.separator).opacity(0.6))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 16) {
                Text("Ready for your first quote")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                setupRow(icon: .tradeTools,
                         title: "Trade",
                         value: tradeName)
                setupRow(icon: .quoteDocument,
                         title: "Quote details",
                         value: businessName)
            }

            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(Color(.statusWarningText))
                    .frame(width: 7, height: 7)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
                Text("Everything you've set up is waiting on the other side of this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    private var tradeName: String {
        model.summaryFacts.first(where: { $0.label == "Trade" })?.value
            ?? "Ready to add"
    }

    private var businessName: String {
        model.summaryFacts.first(where: { $0.label == "Business" })?.value
            ?? "Using your saved defaults"
    }

    private func setupRow(icon: ImageResource, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .foregroundStyle(OnboardingStyle.action)
                .frame(width: 30, height: 30)
                .frame(width: 42, height: 42)
                .background(OnboardingStyle.action.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct OnboardingReviewStep: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(.recordingIntroReview)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .padding(.vertical, 8)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Worth a\nword?")
                    .font(.robotoSlab(32, relativeTo: .largeTitle))
                    .foregroundStyle(Color(.mainText))
                    .multilineTextAlignment(.center)

                Text("Verbal is built by a very small team. A rating from someone who works in the trade is worth more than any advert we could buy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
    }
}
