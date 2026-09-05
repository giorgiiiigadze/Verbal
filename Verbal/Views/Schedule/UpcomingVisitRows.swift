//
//  UpcomingVisitRows.swift
//  Verbal
//
//  The rows Home draws for booked visits: the compact list row, and the
//  card-shaped one used at the top of the tab.
//

import SwiftUI

struct UpcomingVisitRow: View {
    let visit: ScheduledVisit
    let isNext: Bool
    let statusColor: Color
    let onTap: () -> Void

    var body: some View {
        // Concentric with the card around it: its 22 less the 8 this sits in
        // from the edge. At 12 the two curves were running at different rates.
        let rowShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

        Button(action: onTap) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(statusColor)
                    .frame(width: 3, height: 24)

                Text(visit.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)

                Spacer(minLength: 10)

                // The day and the time together, because they are one fact.
                // The card used to say the day once in a heading above a run of
                // rows, which cost a line of its own to carry a single word and
                // left the time below it reading as a time with no date.
                HStack(spacing: 6) {
                    Text(visit.dayText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(visit.timeText)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(statusColor)
                }
                .lineLimit(1)
                .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isNext ? statusColor.opacity(0.08) : Color.clear, in: rowShape)
            .contentShape(.interaction, rowShape)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(visit.accessibilityText)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }
}

struct UpcomingVisitCardRow: View {
    let visit: ScheduledVisit
    let statusColor: Color
    let statusLabel: String
    let onTap: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let rowShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        Button(action: onTap) {
            HStack(spacing: 12) {
                // The status lives in the leading edge, as it does in Home's
                // compact Upcoming card. That makes the state legible before
                // the row is read, without turning every appointment into a
                // quote-sized status badge.
                Capsule()
                    .fill(statusColor)
                    .frame(width: 3, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(visit.title)
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(visit.date.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(statusColor)

                    Text(statusLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(statusColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                rowShape.fill(Color(.cardSurface))
            }
            .overlay(rowShape.strokeBorder(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.10),
                    radius: 8, x: 0, y: 3)
            .contentShape(.interaction, rowShape)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(visit.accessibilityText)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        if let client = clean(visit.clientName) { return client }
        if let address = clean(visit.address) { return address }
        if let note = clean(visit.note) { return note }
        return visit.whenText
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
