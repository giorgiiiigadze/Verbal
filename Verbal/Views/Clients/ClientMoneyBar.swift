//
//  ClientMoneyBar.swift
//  Verbal
//
//  A compact breakdown of what a client's quoted money became.
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
    /// Built by walking a fixed order rather than grouping, so the chart reads
    /// the same way every time: won first, then what is still in play, then what
    /// isn't.
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

    var body: some View {
        VStack(spacing: 22) {
            donut
            legend
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .animation(.snappy(duration: 0.35), value: total)
    }

    // MARK: - Donut

    private var donut: some View {
        ZStack {
            Circle()
                .stroke(Color(.separator).opacity(0.45), lineWidth: 28)

            ForEach(segments) { segment in
                Circle()
                    .trim(from: segment.start, to: segment.end)
                    .stroke(segment.color,
                            style: StrokeStyle(lineWidth: 28, lineCap: .butt, lineJoin: .round))
                    .rotationEffect(.degrees(-90))
            }

        }
        .frame(width: 184, height: 184)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Client quote breakdown")
        .accessibilityValue(accessibilitySummary)
    }

    private struct Segment: Identifiable {
        let id: String
        let start: CGFloat
        let end: CGFloat
        let color: Color
    }

    private var segments: [Segment] {
        guard total > 0 else { return [] }
        var cursor: CGFloat = 0
        return slices.map { slice in
            let size = CGFloat(slice.amount / total)
            let segment = Segment(id: slice.id,
                                  start: cursor,
                                  end: min(cursor + size, 1),
                                  color: slice.color)
            cursor += size
            return segment
        }
    }

    // MARK: - Key

    private var legend: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 16) {
                ForEach(slices) { slice in
                    HStack(spacing: 7) {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(slice.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(AppCurrency.format(slice.amount, code: currencyCode))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color(.mainText))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollIndicators(.hidden)
    }

    private var accessibilitySummary: String {
        slices
            .map { "\($0.label) \(AppCurrency.format($0.amount, code: currencyCode))" }
            .joined(separator: ", ")
    }
}
