//
//  ScheduleVisitSheet.swift
//  Verbal
//
//  Books a visit in, or corrects one already booked.
//
//  Written to be finishable one-handed on a doorstep: one thing to type, a date
//  that already has a sensible answer in it, and everything else optional.
//

import SwiftUI

struct ScheduleVisitSheet: View {
    /// Set when the sheet opened on a visit that already exists.
    var editing: ScheduledVisit?
    let onSave: (ScheduledVisit) -> Void
    var onDelete: ((ScheduledVisit) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var date = ScheduleVisitSheet.defaultDate
    @State private var note = ""
    @State private var recent: [String] = []
    @FocusState private var titleFocused: Bool

    /// Tomorrow morning. A visit booked on the phone is nearly always "in the
    /// next few days", and a picker that opens on this minute makes the user
    /// scroll past today every time.
    private static var defaultDate: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedTitle.isEmpty }

    /// Names quoted before, offered only while the field is empty. Once there
    /// is something typed they'd be guessing at a sentence that is already
    /// being written.
    private var suggestions: [String] {
        trimmedTitle.isEmpty ? Array(recent.prefix(6)) : []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("Who's it for? (e.g. Mrs. Patel — bathroom)", text: $title)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .foregroundStyle(Color(.mainText))
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .focused($titleFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.fieldFill),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color(.royalBlue600).opacity(0.18), lineWidth: 1)
                        )

                    if !suggestions.isEmpty { recentNames }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("When")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // The system's compact picker, unwrapped. It draws its
                        // own tinted capsules, and a field box around them
                        // would be a box inside a box saying the same thing.
                        DatePicker("",
                                   selection: $date,
                                   in: Date.distantPast...,
                                   displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(Color(.royalBlue600))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Note (optional)")
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

                    if let editing, let onDelete {
                        Button(role: .destructive) {
                            onDelete(editing)
                            dismiss()
                        } label: {
                            Text("Remove this visit")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 16)
                .padding(.horizontal, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Color(.systemBackground))
            .navigationTitle(editing == nil ? "Book a visit" : "Edit visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // A form being committed, so the flat 16pt rectangle rather
                // than a capsule — same shape as the client and rate sheets.
                Button(action: save) {
                    Text(editing == nil ? "Save visit" : "Update visit")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(canSave ? Color(.royalBlue600) : Color(.royalBlue600).opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Color(.systemBackground))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: suggestions)
        .presentationDetents([.height(520)])
        .presentationBackground(Color(.systemBackground))
        .task {
            if let editing {
                title = editing.title
                date = editing.date
                note = editing.note ?? ""
            } else {
                recent = (try? await QuoteService.customerNames()) ?? []
                try? await Task.sleep(for: .seconds(0.35))
                titleFocused = true
            }
        }
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

    private func save() {
        guard canSave else { return }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(ScheduledVisit(id: editing?.id ?? UUID(),
                              title: trimmedTitle,
                              date: date,
                              note: cleanNote.isEmpty ? nil : cleanNote))
        dismiss()
    }
}
