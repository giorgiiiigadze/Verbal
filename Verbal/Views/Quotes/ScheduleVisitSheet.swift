//
//  ScheduleVisitSheet.swift
//  Verbal
//
//  Books a visit in, or corrects one already booked.
//
//  Three steps rather than one form: what the job is, which day, what time.
//  A visit is written in the ten seconds after a phone call, usually one-handed
//  on a doorstep, and a single screen asking four things at once is four
//  decisions to hold at the same time. One question a screen means the answer
//  is always the only thing under the thumb — and it buys each question the
//  room for the control it actually wants, a full month on the day step and a
//  wheel on the time one, neither of which fits a stacked form.
//

import SwiftUI

struct ScheduleVisitSheet: View {
    /// Set when the sheet opened on a visit that already exists.
    var editing: ScheduledVisit?
    let onSave: (ScheduledVisit) -> Void
    var onDelete: ((ScheduledVisit) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .details
    /// Which way the last move went, so the steps slide in from the side they
    /// came from rather than always from the right.
    @State private var isAdvancing = true
    @State private var title = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var note = ""
    @State private var date = ScheduleVisitSheet.defaultDate
    @State private var recent: [String] = []
    /// True while the removal alert is up.
    @State private var confirmingRemoval = false
    @FocusState private var titleFocused: Bool

    private enum Step: Int, CaseIterable, Identifiable, Comparable {
        case details, day, time

        var id: Int { rawValue }

        static func < (lhs: Step, rhs: Step) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The question, asked in the title bar. The screen underneath is then
        /// only the answer, and needs no heading of its own.
        var heading: String {
            switch self {
            case .details: return "What's the job?"
            case .day: return "Which day?"
            case .time: return "What time?"
            }
        }
    }

    /// Tomorrow at the current time. A visit booked on the phone is nearly
    /// always "in the next few days", while the time wheel should begin where
    /// the user already is instead of forcing them back to a fixed morning slot.
    private static var defaultDate: Date {
        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let time = calendar.dateComponents([.hour, .minute], from: now)
        return calendar.date(bySettingHour: time.hour ?? 9,
                             minute: time.minute ?? 0,
                             second: 0,
                             of: tomorrow) ?? tomorrow
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name is the only thing required, and only the step that asks for it
    /// can be blocked — a day and a time always have an answer in them.
    private var canContinue: Bool {
        step != .details || !trimmedTitle.isEmpty
    }

    /// Names quoted before, offered only while the field is empty. Once there
    /// is something typed they'd be guessing at a sentence already being
    /// written.
    private var suggestions: [String] {
        trimmedTitle.isEmpty ? Array(recent.prefix(6)) : []
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                progressBar

                Group {
                    switch step {
                    case .details: detailsStep
                    case .day: dayStep
                    case .time: timeStep
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: isAdvancing ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: isAdvancing ? .leading : .trailing).combined(with: .opacity)
                ))

                Spacer(minLength: 0)
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .navigationTitle(step.heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Back once there is somewhere to go back to. Closing is
                    // still a swipe down from anywhere, so the way out isn't
                    // lost with the button.
                    if step == .details {
                        Button(role: .close) { dismiss() }
                    } else {
                        Button {
                            move(to: Step(rawValue: step.rawValue - 1) ?? .details)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Back")
                    }
                }

                if editing != nil, onDelete != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            confirmingRemoval = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(Color(.statusDeclinedText))
                        .accessibilityLabel("Remove visit")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    // A form being committed, so the flat 16pt rectangle rather
                    // than a capsule — same shape as the client and rate sheets.
                    Button(action: primaryAction) {
                        Text(primaryTitle)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(canContinue ? Color(.royalBlue600) : Color(.royalBlue600).opacity(0.4),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canContinue)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Color(.systemBackground))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: suggestions)
        // Sized for the month grid, which is the tallest of the three. A detent
        // that changed with the step would resize the sheet under the thumb
        // between one question and the next.
        .presentationDetents([.height(580)])
        .presentationBackground(Color(.systemBackground))
        // Same shape as the delete confirmations on Home: a question, the
        // action named plainly, and Cancel. The swipe on the row itself still
        // goes straight through — a swipe is already a deliberate gesture,
        // where this is a button sitting under the thumb that was about to
        // press Next.
        .alert("Remove this visit?", isPresented: $confirmingRemoval) {
            Button("Remove", role: .destructive) {
                if let editing, let onDelete {
                    onDelete(editing)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(trimmedTitle.isEmpty ? (editing?.title ?? "This visit") : trimmedTitle)” comes off your upcoming list. Any quotes you've already made are untouched.")
        }
        .task {
            if let editing {
                title = editing.title
                date = editing.date
                phone = editing.phone ?? ""
                address = editing.address ?? ""
                note = editing.note ?? ""
            } else {
                recent = (try? await QuoteService.customerNames()) ?? []
                try? await Task.sleep(for: .seconds(0.35))
                titleFocused = true
            }
        }
    }

    // MARK: - Steps

    /// Name and description. Both belong to the same question — what is this
    /// visit — so they are asked together and nothing else is on the screen.
    private var detailsStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                TextField("Who's it for? (e.g. Mrs. Patel — bathroom)", text: $title)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(Color(.mainText))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($titleFocused)
                    .onSubmit { if canContinue { move(to: .day) } }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    // Tinted, not white. The sheet behind it is white, so a
                    // white field was a hairline outline around nothing.
                    .background(Color(.fieldFill),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.royalBlue600).opacity(0.18), lineWidth: 1)
                    )

                if !suggestions.isEmpty { recentNames }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Phone (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Client phone number", text: $phone)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(Color(.mainText))
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.fieldFill),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Address (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Street, town, or postcode", text: $address, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1...2)
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.fieldFill),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (optional)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Gate code, what to measure…", text: $note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1...3)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.fieldFill),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                }
            }
            // Room for the keyboard, which covers the lower half of the sheet
            // while this step is the one on screen.
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// A whole month, because "which day" is a question about where a date sits
    /// in the week — the compact field answers it as text and makes the user do
    /// that conversion themselves.
    private var dayStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            DatePicker("",
                       selection: $date,
                       in: Calendar.current.startOfDay(for: Date())...,
                       displayedComponents: [.date])
                .labelsHidden()
                .datePickerStyle(.graphical)
                .tint(Color(.royalBlue600))
                // Its own inset would sit the grid a step in from everything
                // else on the sheet.
                .padding(.horizontal, -8)
        }
    }

    /// The wheel rather than the compact field: this step has the screen to
    /// itself, and a wheel is a thumb-drag where the field is a tap, a popover
    /// and then a drag.
    private var timeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            // What has been answered so far, so the last step isn't a bare
            // wheel with no idea what it belongs to.
            Text("\(trimmedTitle) · \(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            DatePicker("",
                       selection: $date,
                       displayedComponents: [.hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.wheel)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Chrome

    /// Three marks for three questions: where this is, and how much is left.
    /// A step already answered is tappable, so going back doesn't have to be
    /// done one chevron at a time — and a visit being corrected can be jumped
    /// through in either direction, since every answer is already in it.
    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases) { candidate in
                Capsule()
                    .fill(candidate <= step ? Color(.royalBlue600) : Color(.separator))
                    .frame(height: 3)
                    // Expanded past the hairline it draws — 3pt is a mark, not
                    // a target.
                    .contentShape(Rectangle().inset(by: -14))
                    .onTapGesture {
                        guard canJump(to: candidate) else { return }
                        move(to: candidate)
                    }
                    .accessibilityLabel("Step \(candidate.rawValue + 1): \(candidate.heading)")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private func canJump(to candidate: Step) -> Bool {
        if candidate == step { return false }
        // Forward only where the questions in between are already answered.
        return candidate < step || (editing != nil && !trimmedTitle.isEmpty)
    }

    /// The same offer the client sheet makes, in the same shape: people quoted
    /// before are one tap rather than typed again.
    private var recentNames: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { name in
                        Button {
                            title = name
                        } label: {
                            Text(name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color(.blueAccentText))
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(Color(.royalBlue25), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .transition(.opacity)
    }

    private var primaryTitle: String {
        switch step {
        case .details, .day: return "Next"
        case .time: return editing == nil ? "Book visit" : "Update visit"
        }
    }

    // MARK: - Moving

    private func primaryAction() {
        guard canContinue else { return }
        switch step {
        case .details: move(to: .day)
        case .day: move(to: .time)
        case .time: save()
        }
    }

    private func move(to next: Step) {
        isAdvancing = next > step
        // The keyboard belongs to the first step only, and left up it would
        // cover half of the month grid the next one draws.
        titleFocused = false
        withAnimation(.snappy(duration: 0.25)) { step = next }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(ScheduledVisit(id: editing?.id ?? UUID(),
                              title: trimmedTitle,
                              date: date,
                              phone: cleanPhone.isEmpty ? nil : cleanPhone,
                              address: cleanAddress.isEmpty ? nil : cleanAddress,
                              note: cleanNote.isEmpty ? nil : cleanNote,
                              recordedQuoteId: editing?.recordedQuoteId,
                              didPromptForMissedVisit: editing?.didPromptForMissedVisit ?? false))
        dismiss()
    }
}
