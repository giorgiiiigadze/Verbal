//
//  RateCardIntroSheet.swift
//  Verbal
//
//  Shown once, the first time someone opens the rate card. The tag button in
//  the Home header gives no clue what is behind it, and the rate card only pays
//  off later — in a recording that prices itself — so it is worth one screen of
//  explanation before the empty list.
//
//  `AnnouncementSheet`, like the share-link news: this is a notice about
//  something, and the sheet that introduces a feature should look like the
//  other sheet that introduces a feature. It was a full-height screen with a
//  placeholder picture band — the only shape of its kind in the app.
//

import SwiftUI

struct RateCardIntroSheet: View {
    /// Runs when they choose to go on. The sheet dismisses itself either way;
    /// this is what opens the rate card behind it.
    var onContinue: () -> Void

    var body: some View {
        AnnouncementSheet(
            badge: "Rate card",
            // The payoff, not the feature. "Your prices, ready to quote"
            // described the rate card; this says what happens because of it,
            // which is the only reason anyone would fill one in.
            title: "Say the job.\nIt's already priced.",
            // One line each. The longer sentences these were written as wrap to
            // three lines at this width and turn the list into a paragraph.
            points: [
                .init(icon: "tag", text: "Save the prices you charge, once"),
                .init(icon: "waveform", text: "Speak a job and it prices itself"),
                .init(icon: "pencil", text: "Change a price, every quote follows"),
            ],
            actionTitle: "Continue",
            preview: { ratesPreview },
            onAction: onContinue
        )
        // A plain fixed height, for the reason the share-link sheet records:
        // `.presentationSizing(.fitted)` makes a mess of this shape on iPhone.
        .presentationDetents([.height(580)])
    }

    /// Two rates that don't exist, drawn the way real ones are.
    ///
    /// Same geometry as the sample card on the rate card's own empty state —
    /// 18pt radius, 14pt inset, name against price over a divider — so this is
    /// a glimpse of the place Continue is about to take them.
    private var ratesPreview: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.sampleRates.enumerated()), id: \.offset) { index, rate in
                if index > 0 { Divider() }
                HStack {
                    Text(rate.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(AppCurrency.format(rate.price)) / \(rate.unit)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 11)
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private static let sampleRates: [(name: String, price: Double, unit: String)] = [
        ("Re-tiling", 45, "m²"),
        ("Replace toilet", 90, "each")
    ]
}

#Preview {
    Color(.homeBackground)
        .sheet(isPresented: .constant(true)) {
            RateCardIntroSheet {}
        }
}
