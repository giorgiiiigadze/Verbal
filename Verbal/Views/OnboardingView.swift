//
//  OnboardingView.swift
//  Verbal
//
//  Three screens between installing the app and signing in.
//
//  Deliberately not a carousel of promises. The first screen shows the app
//  doing its one trick, because a voice-to-quote app is easier to prove than to
//  describe; the other two ask the only questions worth asking before there is
//  an account — and both of their answers do real work rather than being
//  collected for their own sake.
//
//  They run before auth, so there is no user to save anything to. Both answers
//  are held on the device and written to the profile on the first sign-in.
//

import SwiftUI

struct OnboardingView: View {
    /// Called when the last step is finished, to hand over to the auth screen.
    var onContinue: () -> Void

    @AppStorage("pendingTrade") private var pendingTrade = ""
    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    @State private var step = 0
    @Namespace private var glass

    private static let trades = [
        "Electrician", "Plumber", "Carpenter", "Tiler",
        "Painter", "Plasterer", "Builder", "Roofer",
        "Landscaper", "Something else"
    ]

    var body: some View {
        ZStack {
            // The same drawn ground as the sign-in screen, so these three and
            // the one they hand over to read as a single entrance rather than
            // as two apps meeting in the middle.
            AuthBackground()

            VStack(alignment: .leading, spacing: 0) {
                header

                Group {
                    switch step {
                    case 0: showcase
                    case 1: tradeStep
                    default: currencyStep
                    }
                }
                // Each step arrives from the side it was going, so the sequence
                // reads as forward motion rather than as three unrelated
                // screens sharing a background.
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 24)),
                    removal: .opacity.combined(with: .offset(x: -24))
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer
            }
            .padding(24)
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 10) {
            Image(.brandMark)
                .resizable()
                .scaledToFit()
                .frame(width: 24)
                .foregroundStyle(Color(.blueAccentText))
            Text("Verbal")
                .font(.robotoSlab(22, relativeTo: .title3))
                .foregroundStyle(Color(.blueAccentText))
            Spacer()
            // Three steps don't need a map, but they do need an end in sight.
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == step
                              ? Color(.blueAccentText)
                              : Color(.blueAccentText).opacity(0.22))
                        .frame(width: index == step ? 16 : 6, height: 6)
                }
            }
            .animation(.spring(duration: 0.3), value: step)
        }
        .padding(.bottom, 28)
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                if step < 2 { step += 1 } else { onContinue() }
            } label: {
                Text(step < 2 ? "Continue" : "Get started")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(.royalBlue600), in: Capsule())
            }
            .buttonStyle(.plain)

            // Never a wall. Both questions have sensible answers already, and
            // nobody should be stuck on the way to the thing they installed the
            // app for.
            if step > 0 {
                Button("Skip") { if step < 2 { step += 1 } else { onContinue() } }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Holds the space so the primary button doesn't jump between
                // steps one and two.
                Color.clear.frame(height: 20)
            }
        }
    }

    // MARK: - Step 1 · what it does

    /// Shown, not described. The transformation is the product, and a sentence
    /// claiming it happens is weaker than eight lines demonstrating it.
    private var showcase: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Say the job.\nGet the quote.")
                .font(.robotoSlab(34, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Text("“Remove the old toilet and fit the new one, ninety. Three mixer taps. Eight metres of the 20 mil pipe.”")
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.blueAccentText).opacity(0.5))
                    .frame(maxWidth: .infinity)

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
            }

            Text("Prices you didn't say are flagged, never guessed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step 2 · trade

    private var tradeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What's your trade?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))

            Text("So a quote knows that “20 mil” means your 20 mil.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // A grid of taps rather than a text field: this is answered once,
            // standing in a van, and a keyboard is the slowest way to say a
            // word the app could have offered.
            FlowLayout(spacing: 8) {
                ForEach(Self.trades, id: \.self) { trade in
                    Button {
                        pendingTrade = pendingTrade == trade ? "" : trade
                    } label: {
                        Text(trade)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(pendingTrade == trade
                                             ? .white : Color(.mainText))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(pendingTrade == trade
                                        ? Color(.royalBlue600) : Color(.cardSurface),
                                        in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    pendingTrade == trade ? .clear : Color(.separator),
                                    lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: pendingTrade)
        }
    }

    // MARK: - Step 3 · currency

    private var currencyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What do you\nprice in?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            // Already answered from the device's region, so for most people
            // this is a screen they confirm rather than fill in. It is asked at
            // all because a rate card saved in the wrong currency is a mess
            // that needs converting later.
            Text("Your quotes and saved rates are priced in this.")
                .font(.callout)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 8) {
                ForEach(AppCurrency.allCases) { option in
                    Button {
                        currencyCode = option.rawValue
                    } label: {
                        Text("\(option.symbol) \(option.rawValue)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(currencyCode == option.rawValue
                                             ? .white : Color(.mainText))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(currencyCode == option.rawValue
                                        ? Color(.royalBlue600) : Color(.cardSurface),
                                        in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    currencyCode == option.rawValue ? .clear : Color(.separator),
                                    lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: currencyCode)

            Text("You can change it later in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Wraps its children onto as many rows as they need.
///
/// A `LazyVGrid` with fixed columns would give every trade the width of
/// "Something else", leaving "Tiler" adrift in a mostly empty cell. These read
/// as words, so they should be sized like words.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var total = CGSize(width: 0, height: 0)

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                total.width = max(total.width, rowWidth)
                total.height += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        total.width = max(total.width, rowWidth)
        total.height += rowHeight
        return total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
