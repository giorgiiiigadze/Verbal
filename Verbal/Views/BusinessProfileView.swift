//
//  BusinessProfileView.swift
//  Verbal
//
//  Settings → Business. Edits the user's business identity and quote defaults.
//

import SwiftUI

struct BusinessProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var businessName = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var taxNumber = ""
    @State private var validityDays = 14
    @State private var terms = ""
    @State private var notes = ""

    @State private var isLoading = true
    @State private var isSaving = false
    @FocusState private var keyboardShown: Bool

    /// Enabled once the user has entered at least one detail (validity always
    /// has a value, so it doesn't count).
    private var hasInput: Bool {
        [businessName, phone, address, taxNumber, terms, notes]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Form {
            Section("Business") {
                TextField("Business name", text: $businessName)
                    .focused($keyboardShown)
            }
            .listRowBackground(Color(.surface))

            Section("Contact") {
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                    .focused($keyboardShown)
                TextField("Address", text: $address, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($keyboardShown)
            }
            .listRowBackground(Color(.surface))

            Section("Tax") {
                TextField("Tax / VAT number", text: $taxNumber)
                    .focused($keyboardShown)
            }
            .listRowBackground(Color(.surface))

            Section {
                Stepper("Valid for \(validityDays) day\(validityDays == 1 ? "" : "s")",
                        value: $validityDays, in: 1...365)
                TextField("Default terms & conditions", text: $terms, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($keyboardShown)
                TextField("Default notes / footer", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($keyboardShown)
            } header: {
                Text("Quote defaults")
            } footer: {
                Text("Shown on new quotes you create — your contact details, standard terms, and notes.")
            }
            .listRowBackground(Color(.surface))
        }
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        .navigationTitle("Business profile")
        .navigationBarTitleDisplayMode(.large)
        .disabled(isLoading)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Save")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Color(.royalBlue600))
                .disabled(isLoading || isSaving || !hasInput)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyboardShown = false }
                    .fontWeight(.semibold)
            }
        }
        .task { await load() }
    }

    private func load() async {
        if let p = try? await BusinessService.fetch() {
            businessName = p.businessName ?? ""
            phone = p.phone ?? ""
            address = p.address ?? ""
            taxNumber = p.taxNumber ?? ""
            validityDays = p.defaultValidityDays
            terms = p.defaultTerms ?? ""
            notes = p.defaultNotes ?? ""
        }
        isLoading = false
    }

    private func save() {
        isSaving = true
        let profile = BusinessProfile(
            businessName: trimmedOrNil(businessName),
            logoUrl: nil,
            phone: trimmedOrNil(phone),
            email: nil, // Derived from the signed-in account in BusinessService.
            address: trimmedOrNil(address),
            taxNumber: trimmedOrNil(taxNumber),
            currency: AppCurrency.current.rawValue,
            defaultValidityDays: validityDays,
            defaultTerms: trimmedOrNil(terms),
            defaultNotes: trimmedOrNil(notes)
        )
        Task {
            try? await BusinessService.save(profile)
            isSaving = false
            dismiss()
        }
    }

    /// Trim whitespace and treat an empty field as nil (so the DB stays clean).
    private func trimmedOrNil(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
