//
//  ClientMoneyBar.swift
//  Verbal
//
//  What a client's money did, as one bar.
//
//  The page used to draw a chart here — first a bar per quote, then a running
//  total climbing left to right. Both were honest and neither answered the
//  question a client page exists for, which is not "when" but "how much of what
//  I quoted this person turned into work". That question has one shape: a
//  quantity split into parts. So the slot holds the split itself, at a fifth of
//  the height, with nothing to aim a thumb at and no 11pt grey labels to read
//  in the sun.
//
//  Colour comes from the status palette the quote rows already wear, so green
//  here means what green means everywhere else in the app.
//

import SwiftUI

struct ClientMoneyBar: View {
    /// Already converted into `currencyCode`.
    let points: [ClientQuotePoint]
    let currencyCode: String

    /// One status's worth of money, and how it is drawn.
    private struct Slice: Identifiable {
        let label: String
        let amount: Double
        let color: Color
        var id: String { label }
    }

    /// Only the statuses this client actually has money in.
    ///
    /// Built by walking a fixed order rather than grouping, so the bar reads
    /// the same way every time — won first, because that is what the page is
    /// about, then what is still in play, then what isn't.
    private var slices: [Slice] {
        let groups: [(String, Color, (ClientQuotePoint) -> Bool)] = [
            ("Won", Color(.statusAcceptedText), { $0.status == "accepted" }),
            ("Waiting", Color(.statusSentText), { $0.status == "sent" || $0.status == "viewed" }),
            ("Declined", Color(.statusDeclinedText), { $0.status == "declined" }),
            ("Expired", Color(.statusMutedText), { $0.status == "expired" }),
            ("Not sent", Color(.statusMutedText).opacity(0.45), { $0.status == "draft" })
        ]
        return groups.compactMap { label, color, match in
            let amount = points.filter(match).reduce(0) { $0 + $1.amount }
            guard amount > 0 else { return nil }
            return Slice(label: label, amount: amount, color: color)
        }
    }

    private var total: Double { slices.reduce(0) { $0 + $1.amount } }

    private static let gap: CGFloat = 4
    /// A slice worth almost nothing still gets a mark — a client's £40 call-out
    /// beside a £12,000 job would otherwise vanish into a hairline and read as
    /// missing rather than as small.
    private static let minimumWidth: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            bar
            legend
        }
        .animation(.snappy(duration: 0.35), value: total)
    }

    // MARK: - The bar

    /// Separate capsules with air between them rather than one bar cut into
    /// pieces: butted together they read as a progress bar filling up, which is
    /// a story about completion that this isn't.
    private var bar: some View {
        GeometryReader { geometry in
            HStack(spacing: Self.gap) {
                ForEach(slices) { slice in
                    Capsule()
                        .fill(
                            .linearGradient(
                                colors: [slice.color.opacity(0.92), slice.color],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: width(of: slice, across: geometry.size.width))
                }
            }
        }
        .frame(height: 18)
    }

    /// Proportional, after the gaps have taken their share of the width and
    /// each slice its floor — so the pieces always add up to the bar.
    private func width(of slice: Slice, across full: CGFloat) -> CGFloat {
        guard total > 0, !slices.isEmpty else { return 0 }
        let gaps = Self.gap * CGFloat(slices.count - 1)
        let floors = Self.minimumWidth * CGFloat(slices.count)
        let free = max(full - gaps - floors, 0)
        return Self.minimumWidth + free * CGFloat(slice.amount / total)
    }

    // MARK: - The key

    /// Wrapped rather than fixed columns, because these are words of different
    /// lengths and a grid would leave "Won" adrift in a third of the screen.
    private var legend: some View {
        FlowLayout(spacing: 16) {
            ForEach(slices) { slice in
                HStack(spacing: 7) {
                    Capsule()
                        .fill(slice.color)
                        .frame(width: 4, height: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slice.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(AppCurrency.format(slice.amount, code: currencyCode))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color(.mainText))
                    }
                }
            }
        }
    }
}
