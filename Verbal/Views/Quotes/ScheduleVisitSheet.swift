//
//  ScheduleVisitSheet.swift
//  Verbal
//
//  Books a visit, or corrects one already booked.
//
//  One screen, not four. It was a wizard — what the job is, where it is, which
//  day, what time — which asked one question at a time on the theory that a
//  visit is written one-handed in the ten seconds after a phone call. That
//  theory held for entering a booking and broke for everything else: a user
//  fixing a time had to walk three screens to reach it, and nobody could see
//  the whole booking at once to check it against what they'd just been told on
//  the phone.
//
//  So: a native form sheet, read top to bottom in the order the phone call
//  gives you the facts. What the job is called, when it is and how long for,
//  who it's for, where. The header carries Cancel and Book, which is the sheet
//  iOS users already know how to leave.
//

import SwiftUI

struct ScheduleVisitSheet: View {
    /// Set when the sheet opened on a visit that already exists.
    var editing: ScheduledVisit?
    let onSave: (ScheduledVisit) -> Void
    var onDelete: ((ScheduledVisit) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var clientName = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var note = ""
    @State private var start = ScheduleVisitSheet.defaultDate
    @State private var end = ScheduleVisitSheet.defaultDate
        .addingTimeInterval(TimeInterval(ScheduledVisit.defaultDurationMinutes * 60))
    /// True once the address row has been opened, so the field replaces the
    /// button in place rather than the row carrying an empty field forever.
    @State private var showingAddressField = false
    @State private var showingNoteField = false
    @State private var showingClientSheet = false
    /// True while the removal alert is up.
    @State private var confirmingRemoval = false
    @FocusState private var titleFocused: Bool
    @FocusState private var addressFocused: Bool
    @FocusState private var noteFocused: Bool

    /// Tomorrow at the current time. A visit booked on the phone is nearly
    /// always "in the next few days", and the time should begin where the user
    /// already is instead of a fixed morning slot.
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

    private var trimmedClient: String {
        clientName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedAddress: String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The name is the only thing a visit can't be booked without. Everything
    /// else on this sheet is something the user may not know yet.
    private var canSave: Bool { !trimmedTitle.isEmpty }

    /// Minutes between the two time controls, floored at the minimum — the end
    /// picker can be dragged behind the start, and a negative visit is not a
    /// thing.
    private var durationMinutes: Int {
        let minutes = Int(end.timeIntervalSince(start) / 60)
        return max(ScheduledVisit.minimumDurationMinutes, minutes)
    }

    /// "1h 30min" — the grey label beside the range. Built from the live state
    /// rather than the model, because the model doesn't exist until Book.
    private var durationText: String {
        let hours = durationMinutes / 60
        let minutes = durationMinutes % 60
        switch (hours, minutes) {
        case (0, _): return "\(minutes)min"
        case (_, 0): return "\(hours)h"
        default: return "\(hours)h \(minutes)min"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    nameField
                    divider
                    whenBlock
                    divider
                    clientRow
                    divider
                    locationRow
                    divider
                    noteRow
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.homeBackground))
            .navigationTitle(editing == nil ? "New visit" : "Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(.homeBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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

                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Book" : "Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .safeAreaInset(edge: .bottom) {
                // The same action as the header's, in the place the thumb
                // already is. The header button is what makes the sheet read as
                // native; this one is what gets pressed.
                Button(action: save) {
                    Text(editing == nil ? "Book a visit" : "Save changes")
                        .font(.headline)
                        .foregroundStyle(colorScheme == .dark ? Color(.homeBackground) : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(canSave ? Color(.mainText) : Color(.mainText).opacity(0.35),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Color(.homeBackground))
            }
        }
        .background(Color(.homeBackground))
        .sheet(isPresented: $showingClientSheet) {
            ClientSheet(name: $clientName)
        }
        // Same shape as the delete confirmations on Home: a question, the
        // action named plainly, and Cancel.
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
        // Dragging the start moves the whole visit and keeps its length: the
        // user who slides a 90-minute survey from 10 to 11 means it is still 90
        // minutes. Dragging the end is the only way to change the length.
        .onChange(of: start) { previous, current in
            let length = end.timeIntervalSince(previous)
            end = current.addingTimeInterval(max(length, TimeInterval(ScheduledVisit.minimumDurationMinutes * 60)))
        }
        .onChange(of: clientName) { _, name in
            // A client picked on a visit with no address yet: use the one
            // already on file for them rather than asking for it again.
            guard trimmedAddress.isEmpty else { return }
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            Task {
                if let known = try? await QuoteService.customerAddress(named: name),
                   trimmedAddress.isEmpty {
                    address = known
                    showingAddressField = true
                }
            }
        }
        .task {
            if let editing {
                title = editing.title
                clientName = editing.clientName ?? ""
                start = editing.date
                end = editing.endDate
                phone = editing.phone ?? ""
                address = editing.address ?? ""
                note = editing.note ?? ""
                showingAddressField = !(editing.address ?? "").isEmpty
                showingNoteField = !(editing.note ?? "").isEmpty
            } else {
                try? await Task.sleep(for: .seconds(0.35))
                titleFocused = true
            }
        }
    }

    // MARK: - Blocks

    private var divider: some View {
        Divider()
            .overlay(Color(.separator).opacity(0.6))
            .padding(.leading, 24)
    }

    /// The name, in the size of a heading, because it is the one thing on this
    /// sheet that titles everything else.
    private var nameField: some View {
        TextField("Quote name", text: $title)
            .textFieldStyle(.plain)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Color(.mainText))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .focused($titleFocused)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
    }

    /// When it is and how long for, as one question. A start, an end, and the
    /// length between them stated rather than left to be worked out.
    private var whenBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            rowIcon("clock")

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    DatePicker("Starts",
                               selection: $start,
                               displayedComponents: [.hourAndMinute])
                        .labelsHidden()

                    Image(systemName: "arrow.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    DatePicker("Ends",
                               selection: $end,
                               displayedComponents: [.hourAndMinute])
                        .labelsHidden()

                    Text(durationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Lasts \(durationText)")
                }

                DatePicker("Day",
                           selection: $start,
                           in: Calendar.current.startOfDay(for: Date())...,
                           displayedComponents: [.date])
                    .labelsHidden()
            }
            .tint(Color(.blueAccentText))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var clientRow: some View {
        Button {
            showingClientSheet = true
        } label: {
            HStack(spacing: 14) {
                rowIcon("person")
                Text(trimmedClient.isEmpty ? "Client" : trimmedClient)
                    .font(.body)
                    .foregroundStyle(trimmedClient.isEmpty ? Color.secondary : Color(.mainText))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trimmedClient.isEmpty ? "Add a client" : "Client, \(trimmedClient)")
    }

    /// The address, and the phone with it — both are "how do I reach this job",
    /// and neither is worth a divider of its own.
    private var locationRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showingAddressField {
                HStack(alignment: .top, spacing: 14) {
                    rowIcon("mappin.and.ellipse")
                    TextField("Street, town, or postcode", text: $address, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.words)
                        .focused($addressFocused)
                }
            } else {
                Button {
                    showingAddressField = true
                    addressFocused = true
                } label: {
                    HStack(spacing: 14) {
                        rowIcon("mappin.and.ellipse")
                        Text("Location")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 14) {
                rowIcon("phone")
                TextField("Phone", text: $phone)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(Color(.mainText))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    /// A gate code, a measurement to take. It has always been stored and until
    /// now there was nowhere to type it.
    private var noteRow: some View {
        Group {
            if showingNoteField {
                HStack(alignment: .top, spacing: 14) {
                    rowIcon("text.alignleft")
                    TextField("Anything to remember", text: $note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1...4)
                        .textInputAutocapitalization(.sentences)
                        .focused($noteFocused)
                }
            } else {
                Button {
                    showingNoteField = true
                    noteFocused = true
                } label: {
                    HStack(spacing: 14) {
                        rowIcon("text.alignleft")
                        Text("Note")
                            .font(.body)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    /// Every row starts on the same vertical line, so the icons read as a
    /// column of what-kind-of-thing markers rather than decoration.
    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 22, alignment: .leading)
            .accessibilityHidden(true)
    }

    // MARK: - Saving

    private func save() {
        guard canSave else { return }
        let cleanPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(ScheduledVisit(id: editing?.id ?? UUID(),
                              title: trimmedTitle,
                              clientName: trimmedClient.isEmpty ? nil : trimmedClient,
                              date: start,
                              durationMinutes: durationMinutes,
                              phone: cleanPhone.isEmpty ? nil : cleanPhone,
                              address: trimmedAddress.isEmpty ? nil : trimmedAddress,
                              note: cleanNote.isEmpty ? nil : cleanNote,
                              recordedQuoteId: editing?.recordedQuoteId,
                              didPromptForMissedVisit: editing?.didPromptForMissedVisit ?? false))
        dismiss()
    }
}
