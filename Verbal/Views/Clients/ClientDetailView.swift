//
//  ClientDetailView.swift
//  Verbal
//
//  One person, and whether they are worth chasing.
//
//  The tab lists who has been quoted and what was sent them; this answers the
//  question underneath that — how much of it was won, how often they say yes,
//  and what is still sitting with them unanswered. All of it derived from the
//  quotes already in the session, so there is nothing to fetch and nothing that
//  can disagree with the thread at the bottom of the page.
//

import SwiftUI

struct ClientDetailView: View {
    let client: Client

    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    /// Everything they have been quoted, and the part of it they said yes to.
    /// Both converted, so a client quoted in two currencies gets one figure with
    /// an "≈" rather than nothing at all.
    @State private var quoted: ConvertedTotal = .none
    @State private var won: ConvertedTotal = .none
    @State private var waiting: ConvertedTotal = .none

    private var accepted: [QuoteSummary] {
        client.quotes.filter { $0.effectiveStatus == "accepted" }
    }

    private var declined: [QuoteSummary] {
        client.quotes.filter { $0.effectiveStatus == "declined" }
    }

    private var outstanding: [QuoteSummary] {
        client.quotes.filter { $0.effectiveStatus == "sent" || $0.effectiveStatus == "viewed" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                headline
                stats

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quotes")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    // The same rail the tab draws, so arriving here is a closer
                    // look at what was already on screen rather than a second
                    // way of showing it.
                    ClientThread(quotes: client.quotes)
                        // The tab indents the rail past its client card; here
                        // the thread is the whole width it has.
                        .padding(.leading, -20)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.homeBackground))
        // The name is on the page, in the size it deserves. In the bar it would
        // be said twice, and the page would open with a heading it repeats.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: currencyCode) {
            quoted = await ConvertedTotal.of(client.quotes, in: currencyCode)
            won = await ConvertedTotal.of(accepted, in: currencyCode)
            waiting = await ConvertedTotal.of(outstanding, in: currencyCode)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            InitialsAvatar(name: client.name, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(client.name)
                    .font(.robotoSlab(30, relativeTo: .title))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(span)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// How long they have been a client, and how much they have been sent.
    private var span: String {
        let count = "\(client.quotes.count) quote\(client.quotes.count == 1 ? "" : "s")"
        guard let first = client.quotes.map(\.createdAt).min() else { return count }
        return "Since \(first.formatted(.dateTime.month(.abbreviated).year())) · \(count)"
    }

    // MARK: - The figure

    /// What they are worth, which is what they said yes to — not what they were
    /// asked for. A quoted total on its own flatters every client equally.
    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Won")
                .font(.caption)
                .foregroundStyle(.secondary)
            RollingAmount(value: won.amount, code: currencyCode)
                .font(.robotoSlab(28, relativeTo: .title).monospacedDigit())
                .foregroundStyle(Color(.mainText))
            Text("of \(quoted.formatted(in: currencyCode)) quoted")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Stats

    private var stats: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                stat("Accepted", acceptedText)
                divider
                stat("Average quote", averageText)
            }
            Divider()
            HStack(spacing: 0) {
                stat("Waiting", waitingText, detail: oldestText)
                divider
                stat("Last quoted", client.lastQuoted.map { quoteDateLabel($0) } ?? "—")
            }
        }
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: 0.5)
            .frame(maxHeight: .infinity)
    }

    private func stat(_ label: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.medium).monospacedDigit())
                .foregroundStyle(Color(.mainText))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Out of the ones they have actually answered. Counting the undecided
    /// against them would read as a low rate for a client who simply hasn't
    /// replied yet — and with nothing decided there is no rate to state.
    private var acceptedText: String {
        let decided = accepted.count + declined.count
        guard decided > 0 else { return "None yet" }
        return "\(accepted.count) of \(decided)"
    }

    private var averageText: String {
        guard quoted.counted > 0 else { return "—" }
        return AppCurrency.format(quoted.amount / Double(quoted.counted), code: currencyCode)
    }

    private var waitingText: String {
        waiting.counted > 0 ? waiting.formatted(in: currencyCode) : "Nothing"
    }

    /// Only when something is waiting — an age under "Nothing" would be an age
    /// of nothing.
    private var oldestText: String? {
        guard let oldest = outstanding.map(\.createdAt).min() else { return nil }
        return "Oldest \(oldest.formatted(.relative(presentation: .named)))"
    }
}
