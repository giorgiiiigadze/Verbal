//
//  ClientActivityChart.swift
//  Verbal
//
//  A client's history, drawn — as two lines climbing left to right.
//
//  The obvious chart is one mark per quote, and it was that for a while: a bar
//  each, evenly spaced. It reads as a row of blocks rather than as a history,
//  and it can't answer the question the page is for, which is whether this
//  client is worth chasing — a shape answers that, and four blocks have none.
//
//  The line a stock app draws works because a price exists at every instant. A
//  quote doesn't: it is an event, and joining one quote's amount to the next
//  draws a value for every day in between that never existed. What a client does
//  have is a running total — quoted to date, won to date — which is defined
//  every day, holds flat while nothing happens, and steps when something does.
//  Two of them, with the gap between them being everything asked for and not
//  got, is the whole client in one picture.
//

import Charts
import SwiftUI

struct ClientActivityChart: View {
    /// Oldest first, already converted into `currencyCode`.
    let points: [ClientQuotePoint]
    let currencyCode: String
    /// The start of the window on screen, so the lines rise from zero at its
    /// edge rather than from the first quote inside it. Nil for "All".
    var windowStart: Date?

    /// The quote the user is holding, and nothing outside this view's business.
    /// A touch on a mark is a question about that mark, answered in the caption
    /// a few points above it — the page it sits on doesn't move and doesn't need
    /// to know.
    @State private var selected: UUID?

    private var series: [ClientRunningTotal] {
        points.runningTotals(from: windowStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            caption
            chart.frame(height: 148)
        }
        .animation(.snappy(duration: 0.3), value: selected)
    }

    // MARK: - The caption above it

    /// One line, doing two jobs: what the lines mean, until the user touches a
    /// mark, and then what they are touching.
    ///
    /// Both states are stacked over a template that is laid out and never drawn,
    /// so the line keeps the height of the taller of them whichever is showing.
    /// Without it the swap changed the height — the legend is a size smaller
    /// than the detail — and the chart, the Details card and the whole list
    /// below stepped down a few points under the user's thumb and back up when
    /// they let go. A fixed height would fix it and then clip the caption for
    /// anyone running large text; sizing off a real `Text` in the real font
    /// scales the way the caption does.
    private var caption: some View {
        ZStack(alignment: .leading) {
            Text("Ag").font(.footnote.weight(.medium)).hidden()

            if let point = selectedPoint {
                HStack(spacing: 8) {
                    Text(point.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(AppCurrency.format(point.amount, code: currencyCode))
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(point.isWon ? Self.wonColor : Color(.mainText))
                }
            } else {
                HStack(spacing: 12) {
                    key("Quoted", Self.quotedColor)
                    key("Won", Self.wonColor)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func key(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - The lines

    private var chart: some View {
        Chart {
            ForEach(series) { step in
                // Under the won line only. Filling under the quoted one too
                // would put the client's best figure inside the shape of their
                // worst, and the gap between the lines is the reading.
                AreaMark(x: .value("Date", step.date), y: .value("Won", step.won))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(
                        .linearGradient(colors: [Self.wonColor.opacity(0.16), Self.wonColor.opacity(0.01)],
                                        startPoint: .top, endPoint: .bottom)
                    )
                // Stepped, not curved. The total changed on the day the quote
                // went out and on no day either side of it, and a smoothed
                // curve would claim it crept up over the week between.
                //
                // `series:` is not optional here, whatever it looks like. Two
                // LineMarks with nothing to tell them apart are one series to
                // Charts, and it joins them into a single line that zig-zags
                // between the two totals — a saw-tooth that looks like data.
                LineMark(x: .value("Date", step.date),
                         y: .value("Quoted", step.quoted),
                         series: .value("Line", "quoted"))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Self.quotedColor)
                LineMark(x: .value("Date", step.date),
                         y: .value("Won", step.won),
                         series: .value("Line", "won"))
                    .interpolationMethod(.stepEnd)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(Self.wonColor)
            }

            // A dot at each quote, at the top of the step it caused. Four quotes
            // stay visibly four events this way — the line gives the shape, the
            // dots stop it passing itself off as a dense series.
            ForEach(series) { step in
                if let quote = step.quote {
                    PointMark(x: .value("Date", step.date), y: .value("Quoted", step.quoted))
                        .symbolSize(quote.id == selected ? 90 : 40)
                        .foregroundStyle(quote.isWon ? Self.wonColor : Self.quotedColor)
                }
            }

            if let point = selectedPoint {
                RuleMark(x: .value("Date", point.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(Color(.separator))
            }
        }
        .chartYAxis { moneyAxis }
        .chartXAxis { dateAxis }
        // A little room past today, so the last date label has somewhere to sit
        // rather than being clipped against the right edge of the plot.
        .chartXScale(domain: domain)
        .chartOverlay { proxy in
            tapCatcher(proxy) { x in
                guard let date: Date = proxy.value(atX: x) else { return nil }
                return nearest(to: date)?.id
            }
        }
    }

    private var domain: ClosedRange<Date> {
        guard let first = series.first?.date, let last = series.last?.date else {
            return Date()...Date()
        }
        // Enough that the final tick isn't sitting on the edge — a label
        // centred there loses its right half to the plot boundary.
        let margin = max(last.timeIntervalSince(first) * 0.12, 43_200)
        return first...last.addingTimeInterval(margin)
    }

    private func nearest(to date: Date) -> ClientQuotePoint? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
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

    // MARK: - Axes

    private var selectedPoint: ClientQuotePoint? {
        selected.flatMap { id in points.first { $0.id == id } }
    }

    /// A label under each dot, not on a tidy grid.
    ///
    /// Evenly spaced ticks are right for a price, which has a value on every one
    /// of them. Here they landed on days nothing happened — "Aug 14" under a
    /// flat stretch — leaving the reader to work out which date each step
    /// belonged to. The dates that matter are the ones quotes went out on, so
    /// those are the ones on the axis, and every label now points at a mark
    /// above it.
    private var dateAxis: some AxisContent {
        AxisMarks(values: labelledDates) { _ in
            AxisValueLabel(format: dateFormat)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// One per day a quote landed — two quotes on one day share a step, so they
    /// share a label — with any that would collide dropped.
    ///
    /// Walked from the right, because the newest end of a chart that runs to
    /// today is where the eye starts and the label worth keeping is the recent
    /// one. A date is kept only if it clears the last kept one by enough of the
    /// span to have somewhere to print: two quotes a day apart in a fortnight's
    /// window otherwise draw "Aug 16" and "Aug 17" on top of each other.
    private var labelledDates: [Date] {
        let calendar = Calendar.current
        var seen: Set<Date> = []
        let days = points
            .filter { seen.insert(calendar.startOfDay(for: $0.date)).inserted }
            .map(\.date)

        guard let first = days.first, let last = days.last, first != last else { return days }
        let minimumGap = last.timeIntervalSince(first) * 0.16

        var kept: [Date] = []
        for date in days.reversed() {
            if let previous = kept.last, previous.timeIntervalSince(date) < minimumGap { continue }
            kept.append(date)
        }
        return kept.reversed()
    }

    private var dateFormat: Date.FormatStyle {
        guard let first = series.first?.date, let last = series.last?.date else {
            return .dateTime.month(.abbreviated)
        }
        let days = last.timeIntervalSince(first) / 86_400
        if days <= 60 { return .dateTime.month(.abbreviated).day() }
        if days <= 730 { return .dateTime.month(.abbreviated) }
        return .dateTime.month(.abbreviated).year(.twoDigits)
    }

    /// Three gridlines and short money, because the shape of the climb is the
    /// reading — the exact figure is one tap away and printed in the caption
    /// when it is.
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
    // One accent and a grey. The reference this borrows its shape from paints
    // its line red or green because a share price has only those two things to
    // say; a running total never falls, so red would have nothing to report and
    // would only be the loudest thing on a quiet page. Won carries the accent
    // because won is what anyone opens this page looking for, and quoted is the
    // grey line it is measured against.

    private static let wonColor = Color(.statusAcceptedText)
    private static let quotedColor = Color(.statusMutedText).opacity(0.45)
}
