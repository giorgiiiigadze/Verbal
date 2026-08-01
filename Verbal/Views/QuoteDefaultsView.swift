//
//  QuoteDefaultsView.swift
//  Verbal
//
//  Settings → Quote defaults. Values that pre-fill every new quote: how long
//  it's valid, plus standard terms and notes. Saved onto the same
//  business_profiles row as the profile identity.
//

import SwiftUI

struct QuoteDefaultsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var validityDays = 14
    /// Percentage as typed, e.g. "20". Empty means not tax registered.
    @State private var taxRate = ""
    @State private var terms = ""
    @State private var notes = ""

    /// The full row as loaded, so saving our subset preserves the identity fields.
    @State private var loaded = BusinessProfile.empty
    @State private var isLoading = true
    @State private var isSaving = false
    @FocusState private var keyboardShown: Bool

    /// Typed rate as a number; blank or unparseable means no tax.
    private var taxRateValue: Double {
        Double(taxRate.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var isDirty: Bool {
        validityDays != loaded.defaultValidityDays
            || taxRateValue != loaded.defaultTaxRate
            || terms != (loaded.defaultTerms ?? "")
            || notes != (loaded.defaultNotes ?? "")
    }

    var body: some View {
        ZStack {
            Color(.homeBackground).ignoresSafeArea()
            Form {
            Section {
                Stepper("Valid for \(validityDays) day\(validityDays == 1 ? "" : "s")",
                        value: $validityDays, in: 1...365)
            } footer: {
                Text("How long a new quote stays valid for.")
            }
            .listRowBackground(Color(.surface))

            Section {
                LabeledContent("Tax rate") {
                    HStack(spacing: 4) {
                        TextField("0", text: $taxRate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($keyboardShown)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Tax")
            } footer: {
                Text("Added to new quotes and shown as a separate line on the PDF. Leave at 0 if you're not tax registered.")
            }
            .listRowBackground(Color(.surface))

            Section("Terms & conditions") {
                TextField("Standard terms shown on every quote", text: $terms, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($keyboardShown)
            }
            .listRowBackground(Color(.surface))

            Section("Notes / footer") {
                TextField("A note added to the bottom of each quote", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($keyboardShown)
            }
            .listRowBackground(Color(.surface))
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Quote defaults")
        .navigationBarTitleDisplayMode(.large)
        .disabled(isLoading)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isLoading || !isDirty)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyboardShown = false }.fontWeight(.semibold)
            }
        }
        .task { await load() }
        }
    }

    /// "20" rather than "20.0", but keeps a real fraction like 8.5.
    private func trimmedRate(_ rate: Double) -> String {
        rate == rate.rounded() ? String(Int(rate)) : String(rate)
    }

    private func load() async {
        if let cached = session.businessProfile {
            loaded = cached
        } else if let fetched = try? await BusinessService.fetch() {
            loaded = fetched
        }
        validityDays = loaded.defaultValidityDays
        taxRate = loaded.defaultTaxRate == 0 ? "" : trimmedRate(loaded.defaultTaxRate)
        terms = loaded.defaultTerms ?? ""
        notes = loaded.defaultNotes ?? ""
        isLoading = false
    }

    private func save() {
        isSaving = true
        var profile = loaded
        profile.defaultValidityDays = validityDays
        profile.defaultTaxRate = taxRateValue
        profile.defaultTerms = trimmedOrNil(terms)
        profile.defaultNotes = trimmedOrNil(notes)
        Task {
            try? await BusinessService.save(profile)
            session.cacheBusinessProfile(profile)
            isSaving = false
            dismiss()
        }
    }

    private func trimmedOrNil(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
