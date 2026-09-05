//
//  VisitActionSheet.swift
//  Verbal
//
//  The sheet a booked visit opens into, and the classification that decides
//  which actions it offers. Shared by Home's Upcoming list and the Schedule tab.
//

import SwiftUI

enum VisitAction {
    case future, happeningNow, passed, recorded(QuoteSummary?)
}

struct VisitActionSheet: View {
    /// The same bright blue as Home's floating Record control. Visit actions
    /// lead into the very same recording flow, so their primary controls
    /// should not introduce a competing shade of blue.
    private static let recordBlue = Color(.royalBlue600)

    let visit: ScheduledVisit
    let action: VisitAction
    let onPrimary: () -> Void
    let onDirections: () -> Void
    let onCall: () -> Void
    let onReschedule: () -> Void
    let onCancel: () -> Void
    let onDidNotHappen: () -> Void
    let onOpenQuote: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    visitDetails
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.homeBackground))
            .navigationTitle("Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .background(Color(.homeBackground))
            }
        }
        // Opens at a mid detent — enough to read the visit's headline facts and
        // reach the primary actions — with the handle inviting a drag up when
        // the full note or address needs the room.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.homeBackground))
    }

    private var visitDetails: some View {
        Group {
            Text(visit.title)
                .font(.robotoSlab(29, relativeTo: .title))
                .foregroundStyle(Color(.mainText))
                .lineLimit(2)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            divider

            HStack(alignment: .top, spacing: 14) {
                assetIcon("VisitClock")
                Text("\(visit.date.formatted(.dateTime.weekday(.wide).month(.wide).day())) · \(visit.timeRangeText)")
                    .font(.body)
                    .foregroundStyle(Color(.mainText))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            divider

            HStack(spacing: 14) {
                assetIcon("VisitClient")
                Text(value(visit.clientName, placeholder: "Client"))
                    .font(.body)
                    .foregroundStyle(hasValue(visit.clientName) ? Color(.mainText) : .secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            divider

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    assetIcon("LocationPin")
                    Text(value(visit.address, placeholder: "Location"))
                        .font(.body)
                        .foregroundStyle(hasValue(visit.address) ? Color(.mainText) : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 14) {
                    assetIcon("PhoneCall")
                    Text(value(visit.phone, placeholder: "Phone"))
                        .font(.body)
                        .foregroundStyle(hasValue(visit.phone) ? Color(.mainText) : .secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            divider

            HStack(alignment: .top, spacing: 14) {
                assetIcon("VisitNote")
                Text(value(visit.note, placeholder: "Note"))
                    .font(.body)
                    .foregroundStyle(hasValue(visit.note) ? Color(.mainText) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

    private var divider: some View {
        Divider()
            .overlay(Color(.separator).opacity(0.6))
            .padding(.horizontal, 24)
    }

    private func systemIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 22, alignment: .leading)
            .accessibilityHidden(true)
    }

    private func assetIcon(_ name: String) -> some View {
        Image(name)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }

    private func hasValue(_ value: String?) -> Bool {
        !(value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private func value(_ value: String?, placeholder: String) -> String {
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? placeholder : clean
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch action {
        case .future:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    borderedBlueButton("Directions", action: onDirections)
                    borderedBlueButton("Reschedule", action: onReschedule)
                }
                filledPrimaryButton("Call client", action: onCall)
                borderedDestructiveButton("Cancel", action: onCancel)
            }
        case .passed:
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    filledPrimaryButton(primaryTitle, action: onPrimary)
                    borderedBlueButton("Reschedule", action: onReschedule)
                }
                borderedDestructiveButton("Didn't happen", action: onDidNotHappen)
            }
        case .happeningNow:
            // A visit that is underway can still slip — the client can move it
            // half an hour on the doorstep, or take a call and stand you down.
            // Reschedule and Cancel need to reach into this window; the earlier
            // layout hid both, so the sheet was read-only for up to two hours.
            VStack(spacing: 10) {
                filledPrimaryButton(primaryTitle, action: onPrimary)
                HStack(spacing: 10) {
                    borderedBlueButton("Directions", action: onDirections)
                    borderedBlueButton("Reschedule", action: onReschedule)
                }
                filledPrimaryButton("Call client", action: onCall)
                borderedDestructiveButton("Cancel", action: onCancel)
            }
        case .recorded:
            // The quote is the durable artefact, but the visit row that lives
            // beside it can still be wrong — a typo in the client name, the
            // wrong end time. Let the calendar entry be edited without touching
            // the quote it's linked to.
            VStack(spacing: 10) {
                filledPrimaryButton(primaryTitle, action: onPrimary)
                borderedBlueButton("Reschedule", action: onReschedule)
            }
        }
    }

    private var primaryTitle: String {
        switch action {
        case .future: return "Directions"
        case .happeningNow: return "Start recording"
        case .passed: return "Record now"
        case .recorded: return "Open quote"
        }
    }

    private func secondaryButton(_ title: String,
                                 role: ButtonRole? = nil,
                                 action: @escaping () -> Void) -> some View {
        Button(role: role) {
            closeThen(action)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color(.statusDeclinedText) : Color(.blueAccentText))
    }

    private func filledPrimaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            closeThen(action)
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Self.recordBlue,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func borderedDestructiveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            closeThen(action)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(.statusDeclinedText))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(.statusDeclinedFill),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.statusDeclinedText).opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func borderedBlueButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            closeThen(action)
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
        .foregroundStyle(Self.recordBlue)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Self.recordBlue.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Self.recordBlue.opacity(0.32), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func closeThen(_ action: @escaping () -> Void) {
        dismiss()
        Task {
            try? await Task.sleep(for: .seconds(0.25))
            await MainActor.run { action() }
        }
    }
}
