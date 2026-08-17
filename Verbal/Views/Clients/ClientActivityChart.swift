//
//  ClientActivityChart.swift
//  Verbal
//
//  A client's history, drawn.
//
//  Two shapes, one view, and the switch between them is the whole point. A
//  trade with four quotes to a client has no curve — a line through four dots
//  is a picture of nothing, drawn with the confidence of a picture of
//  something — so a short history plots as one bar per quote, where each mark
//  is a real event and its height is a real amount. Once there are enough of
//  them for a shape to mean anything, it becomes the cumulative won line: it
//  only ever climbs, and how long it has been flat is exactly the thing a
//  client page is for.
//

import Charts
import SwiftUI

struct ClientActivityChart: View {
    /// Oldest first, already converted into `currencyCode`.
    let points: [ClientQuotePoint]
    let currencyCode: String

    /// The quote the user is holding, and nothing outside this view's business.
    /// A touch on a mark is a question about that mark, answered in the caption
    /// a few points above it — the page it sits on doesn't move and doesn't need
    /// to know.
    @State private var selected: UUID?

    /// Below this a history has events; at or above it, it has a shape.
    private static let lineThreshold = 8

    private var usesLine: Bool { points.count >= Self.lineThreshold }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption
            Group {
                if usesLine {
                    wonLine
                } else {
                    quoteBars
                }
            }
            .frame(height: 148)
        }
        .animation(.snappy(duration: 0.3), value: selected)
    }

    // MARK: - The caption above it

    /// One line, doing two jobs: what the colours mean, until the user touches
    /// a mark, and then what they are touching. Swapping in place keeps the
    /// chart from stepping down the page mid-gesture.
    @ViewBuilder private var caption: some View {
        if let point = selectedPoint {
            HStack(spacing: 8) {
                Text(point.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(AppCurrency.format(point.amount, code: currencyCode))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color(for: point))
            }
        } else {
            HStack(spacing: 12) {
                ForEach(legend, id: \.label) { entry in
                    HStack(spacing: 5) {
                        Circle().fill(entry.color).frame(width: 6, height: 6)
                        Text(entry.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// Only the statuses actually on the chart — a key to marks that aren't
    /// there is noise, and with four quotes it would be most of the key.
    private var legend: [(label: String, color: Color)] {
        var entries: [(String, Color)] = []
        if usesLine {
            entries.append(("Won, running total", Self.wonColor))
        } else {
            if points.contains(where: \.isWon) { entries.append(("Won", Self.wonColor)) }
            if points.contains(where: \.isWaiting) { entries.append(("Waiting", Self.waitingColor)) }
            if points.contains(where: \.isDeclined) { entries.append(("Declined", Self.coldColor)) }
        }
        return entries
    }

    // MARK: - Bars: one quote, one mark

    /// Plotted against position rather than date. Two quotes sent in the same
    /// week would otherwise draw as one thick mark and a year-old third would
    /// sit alone at the far edge; evenly spaced, four quotes read as four
    /// quotes, and the dates on the axis carry the timing.
    private var quoteBars: some View {
        Chart {
            ForEach(points) { point in
                BarMark(x: .value("Quote", point.id.uuidString),
                        y: .value("Amount", point.amount),
                        width: .ratio(0.5))
                    .foregroundStyle(color(for: point))
                    .opacity(dimmed(point) ? 0.3 : 1)
                    .cornerRadius(5)
            }
        }
        // One category per quote, in date order, keyed on the quote's own id.
        //
        // The x here is a name, not a number, and it has to be a type Charts
        // treats as one: a position given as an Int reads back as a measurement
        // on a number line, and asking for a band scale over it trips an
        // assertion inside Charts and takes the app down with it. A String
        // domain is unambiguously categorical, which is what a row of quotes
        // is — evenly spaced slots, with the dates on the axis carrying the
        // timing. (Plotted against the real dates instead, two quotes sent in
        // one week would draw as a single thick mark.)
        .chartXScale(domain: points.map(\.id.uuidString))
        .chartXAxis { dateAxis }
        .chartYAxis { moneyAxis }
        .chartOverlay { proxy in
            tapCatcher(proxy) { x in
                guard let name: String = proxy.value(atX: x) else { return nil }
                return points.first { $0.id.uuidString == name }?.id
            }
        }
    }

    // MARK: - Line: what has been won, running

    /// Every quote moves the line along; only an accepted one moves it up. The
    /// series is carried to today so a client who has gone quiet shows it as a
    /// flat run to the right edge rather than stopping at their last quote.
    private var wonLine: some View {
        Chart {
            ForEach(cumulative, id: \.date) { step in
                AreaMark(x: .value("Date", step.date), y: .value("Won", step.amount))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(
                        .linearGradient(colors: [Self.wonColor.opacity(0.18), Self.wonColor.opacity(0.01)],
                                        startPoint: .top, endPoint: .bottom)
                    )
                LineMark(x: .value("Date", step.date), y: .value("Won", step.amount))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Self.wonColor)
            }
            if let point = selectedPoint {
                RuleMark(x: .value("Date", point.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color(.separator))
                PointMark(x: .value("Date", point.date),
                          y: .value("Won", wonSoFar(at: point.date)))
                    .symbolSize(60)
                    .foregroundStyle(color(for: point))
            }
        }
        .chartYAxis { moneyAxis }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartOverlay { proxy in
            tapCatcher(proxy) { x in
                guard let date: Date = proxy.value(atX: x) else { return nil }
                return nearest(to: date)?.id
            }
        }
    }

    /// A tap anywhere over the plot picks the mark under it.
    ///
    /// `chartXSelection` would be the obvious way to do this and isn't: it
    /// treats a touch as a gesture to be tracked, and hands back `nil` the
    /// moment the finger lifts, so a tap selects and deselects in one motion and
    /// nothing ever appears in the caption. Reading the x position ourselves
    /// makes the selection a state the user set rather than a gesture they are
    /// mid-way through — tap a mark to name it, tap it again to put it away.
    private func tapCatcher(_ proxy: ChartProxy,
                            markAt: @escaping (CGFloat) -> UUID?) -> some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    guard let plot = proxy.plotFrame else { return }
                    let id = markAt(location.x - geometry[plot].origin.x)
                    selected = (id == selected) ? nil : id
                }
        }
    }

    /// The running won total after each quote, with a zero before the first so
    /// the climb starts from the floor, and a flat carry to today at the end.
    private var cumulative: [(date: Date, amount: Double)] {
        guard let first = points.first else { return [] }
        var running = 0.0
        var steps: [(date: Date, amount: Double)] = [(first.date.addingTimeInterval(-86_400), 0)]
        for point in points {
            if point.isWon { running += point.amount }
            steps.append((point.date, running))
        }
        steps.append((Date(), running))
        return steps
    }

    private func wonSoFar(at date: Date) -> Double {
        points.filter { $0.isWon && $0.date <= date }.reduce(0) { $0 + $1.amount }
    }

    private func nearest(to date: Date) -> ClientQuotePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    // MARK: - Shared furniture

    private var selectedPoint: ClientQuotePoint? {
        selected.flatMap { id in points.first { $0.id == id } }
    }

    private func dimmed(_ point: ClientQuotePoint) -> Bool {
        selected != nil && selected != point.id
    }

    /// When each bar was sent, under the bar it belongs to.
    ///
    /// The x values come back as the ids the scale is keyed on, so each label is
    /// a lookup rather than a format of the value itself. Past five bars the
    /// labels stop fitting side by side, and every other one is dropped — a
    /// crowded axis is read as a smear, and the bars are evenly spaced, so the
    /// dates that remain still place the ones between them.
    private var dateAxis: some AxisContent {
        AxisMarks { value in
            AxisValueLabel {
                if let name = value.as(String.self),
                   let index = points.firstIndex(where: { $0.id.uuidString == name }),
                   index % labelStride == 0 {
                    Text(points[index].date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var labelStride: Int { points.count > 5 ? 2 : 1 }

    /// Three gridlines and short money, because the height of a bar against its
    /// neighbours is the reading — the exact figure is one tap away and printed
    /// in the caption when it is.
    private var moneyAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(Color(.separator))
            AxisValueLabel {
                if let amount = value.as(Double.self) {
                    Text(compact(amount))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "$4K" — the axis has room for a shape, not for a total.
    private func compact(_ amount: Double) -> String {
        let symbol = AppCurrency(rawValue: currencyCode)?.symbol ?? ""
        let number = amount.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
        return symbol + number
    }

    // MARK: - Colour
    //
    // One accent, and grey. The reference this borrows its layout from paints
    // every mark red or green because a share price has only those two things
    // to say; a quote has four statuses, and four colours across a page this
    // quiet would be the loudest thing in the app. Won carries the accent
    // because won is the only thing on this page anyone is looking for.

    private static let wonColor = Color(.statusAcceptedText)
    private static let waitingColor = Color(.mainText).opacity(0.32)
    private static let coldColor = Color(.statusMutedText).opacity(0.3)

    private func color(for point: ClientQuotePoint) -> Color {
        if point.isWon { return Self.wonColor }
        if point.isWaiting { return Self.waitingColor }
        return Self.coldColor
    }
}
