//
//  OnboardingPhoneScreen.swift
//  Verbal
//
//  What shows through the glass of the phone on the opening screen: a quote,
//  built the way a real one is built.
//
//  Not an illustration of the app — the same `LineItemsCard` and `LineItemRow`
//  the quote screen uses, laid out the way `QuoteDetailView` lays them out. A
//  drawn approximation would have to be kept in step with the real screen by
//  hand, and wouldn't be, so the first thing anyone sees would slowly stop
//  being true.
//

import SwiftUI

struct OnboardingPhoneScreen: View {
    /// The quote's currency. Passed in rather than read here so this renders the
    /// same symbol the rest of onboarding is using.
    let currencyCode: String

    /// The width this is composed at, then scaled down to fit whatever glass it
    /// is given. Laid out directly at the ~237pt of the frame, every font would
    /// be at its natural size in a screen 60% the width of a real one — a phone
    /// stuck in accessibility text rather than a photograph of one.
    private static let referenceWidth: CGFloat = 393
    private static let referenceHeight: CGFloat = 852

    /// The same job the rest of onboarding uses. One example throughout: the
    /// reveal falls back to this toilet too, and a second invented job would
    /// read as two different demos rather than one product.
    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / Self.referenceWidth
            screen
                .frame(width: Self.referenceWidth, height: Self.referenceHeight)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geometry.size.width,
                       height: geometry.size.height,
                       alignment: .topLeading)
        }
    }

    private var screen: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Bathroom, 14 Prospect Row")
                    .font(.robotoSlab(34, relativeTo: .largeTitle))
                    .foregroundStyle(Color(.mainText))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Summary")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color(.mainText))
                    Text("Swap the toilet, fit three mixer taps, run new pipe.")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(Color(.mainText))
                        .fixedSize(horizontal: false, vertical: true)
                }

                ScopeList(items: [
                    "Isolate the supply and remove the old suite",
                    "Fit the new pan, cistern and seat",
                    "Run new 20 mil pipe to the basin"
                ])
                .padding(.top, 4)

                LineItemsCard {
                    LineItemRow(description: "Remove old toilet and fit new toilet",
                                quantityText: "1 each", isMissingPrice: false,
                                lineTotal: 90, currencyCode: currencyCode)
                    Divider()
                    LineItemRow(description: "Mixer taps", quantityText: "3 each",
                                isMissingPrice: true, lineTotal: nil,
                                currencyCode: currencyCode)
                    Divider()
                    LineItemRow(description: "20 mil pipe", quantityText: "8 m",
                                isMissingPrice: true, lineTotal: nil,
                                currencyCode: currencyCode)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            // The frame draws its own island over whatever is underneath, so
            // the content has to start below it the way a real screen's does —
            // at 12 the quote's title ran under the cutout.
            .padding(.top, 64)

            Spacer(minLength: 0)

            totalBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.homeBackground))
    }

    /// The quote screen's own bottom bar. The unpriced note is the point of
    /// showing it: two of the three lines were never given a price, and the app
    /// says so instead of totalling around it.
    private var totalBar: some View {
        HStack {
            Text("Total")
                .font(.headline)
                .foregroundStyle(Color(.mainText))
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(90, format: AppCurrency.format(code: currencyCode))
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color(.mainText))
                Text("excl. 2 unpriced items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        // The home indicator's room. Without it the bar sits flush on the
        // bottom bezel, which no running app ever does.
        .padding(.bottom, 34)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
