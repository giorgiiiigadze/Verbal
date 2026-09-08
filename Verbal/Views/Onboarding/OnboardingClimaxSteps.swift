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
        VStack(alignment: .leading, spacing: 22) {
            OnboardingHeading(title: "You're set up.")

            OnboardingCard(tinted: true) {
                tally(value: "\(model.draftRates.count)",
                      label: model.draftRates.count == 1 ? "rate on your card" : "rates on your card")
            }

            Text("Everything you've set up is waiting on the other side of this.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    private func tally(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(value)
                .font(.robotoSlab(34, relativeTo: .largeTitle))
                .foregroundStyle(OnboardingStyle.action)
            Text(label)
                .font(.callout)
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
        }
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
