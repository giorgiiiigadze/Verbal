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
    @State private var drawProgress: CGFloat = 0

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
    /// The chart's own colours for the two ends of the story, and for the
    /// quotes that never left.
    ///
    /// Deliberately not the status colours the pills use, which is the one
    /// place in the app where the same status is drawn two ways on purpose. A
    /// pill is small type on a tinted ground and has to stay legible there; a
    /// segment is a block of colour a centimetre wide with nothing on it, and
    /// the value that reads well as one reads washed out as the other. Won and
    /// Declined are the figures this page is about, so they get the colours
    /// that carry across a room.
    ///
    /// Not sent is violet rather than the grey it shares with the pill: grey
    /// was saying two things in one chart, and only one of them was true —
    /// expired is over, a draft is the one slice still waiting on the user.
    /// Not amber either, which is the app's warning colour and is spoken for
    /// by the "unpriced" badge on the rows below.
    private var slices: [Slice] {
        let groups: [(String, Color, (ClientQuotePoint) -> Bool)] = [
            ("Won", Color(.chartWon), { $0.status == "accepted" }),
            ("Waiting", Color(.statusSentText), { $0.status == "sent" || $0.status == "viewed" }),
            ("Declined", Color(.chartDeclined), { $0.status == "declined" }),
            ("Expired", Color(.statusMutedText), { $0.status == "expired" }),
            ("Not sent", Color(.chartDraft), { $0.status == "draft" })
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
        .onAppear { playIntro() }
        .onChange(of: total) { _, _ in playIntro() }
    }

    // MARK: - Donut

    private var donut: some View {
        ZStack {
            Circle()
                .stroke(Color(.separator).opacity(0.45), lineWidth: 28)

            ZStack {
                ForEach(segments) { segment in
                    Circle()
                        .trim(from: segment.start, to: segment.end)
                        .stroke(segment.color,
                                style: StrokeStyle(lineWidth: 28, lineCap: .butt, lineJoin: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .mask {
                Circle()
                    .trim(from: 0, to: drawProgress)
                    .stroke(.black,
                            style: StrokeStyle(lineWidth: 30, lineCap: .butt, lineJoin: .round))
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

    private func playIntro() {
        drawProgress = 0
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(.smooth(duration: 0.85)) {
                drawProgress = 1
            }
        }
    }
}
