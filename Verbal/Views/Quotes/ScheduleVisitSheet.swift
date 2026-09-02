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
//  who it's for, where. The header carries only the way out; booking happens
//  at the bottom button, under the thumb that has just filled the form in.
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

    /// The start, wired so that moving it takes the end with it and keeps the
    /// visit the same length: sliding a 90-minute survey from 10 to 11 leaves
    /// it 90 minutes. Dragging the end is what changes the length.
    ///
    /// Deliberately a binding rather than `.onChange(of: start)`. An observer
    /// cannot tell a user's drag from the sheet populating itself, and it fires
    /// after the view update, by which time any "still loading" flag has
    /// already been set — whether it corrupted the visit came down to when
    /// SwiftUI scheduled a render. A setter runs only when a control is driven,
    /// so loading a visit cannot reach it at all.
    private var startBinding: Binding<Date> {
        Binding {
            start
        } set: { moved in
            let length = max(end.timeIntervalSince(start),
                             TimeInterval(ScheduledVisit.minimumDurationMinutes * 60))
            start = moved
            end = moved.addingTimeInterval(length)
        }
    }

    /// The client, wired the same way: picking someone fills in an address we
    /// already hold for them, while loading a visit that already names them
    /// leaves its address exactly as booked.
    private var clientBinding: Binding<String> {
        Binding {
            clientName
        } set: { picked in
            clientName = picked
            let name = picked.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, trimmedAddress.isEmpty else { return }
            Task {
                if let known = try? await QuoteService.customerAddress(named: name),
                   trimmedAddress.isEmpty {
                    address = known
                    showingAddressField = true
                }
            }
        }
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
                    // The system's own close glyph rather than the word
                    // "Cancel" — nothing has been committed yet, so there is
                    // nothing to cancel, and the sheets elsewhere in the app
                    // are left the same way.
                    Button(role: .close) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // The only way to commit the booking, and it sits where the
                // thumb already is. The header briefly carried a Book button
                // too, which was the same action said twice — the header's job
                // here is the way out, not the way forward.
                VStack(spacing: 10) {
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

                    // Calling off the visit belongs beside saving it, not up in
                    // the corner as a trash glyph: both are things you decide
                    // about the booking in front of you, and a bin icon in a
                    // toolbar is a guess at what it deletes. Same red-outlined
                    // shape the visit's own action sheet uses to cancel it, so
                    // it is recognisably the same decision in both places.
                    if editing != nil, onDelete != nil {
                        Button {
                            confirmingRemoval = true
                        } label: {
                            Text("Cancel visit")
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
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Color(.homeBackground))
            }
        }
        .background(Color(.homeBackground))
        .sheet(isPresented: $showingClientSheet) {
            ClientSheet(name: clientBinding)
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
                               selection: startBinding,
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
                           selection: startBinding,
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
