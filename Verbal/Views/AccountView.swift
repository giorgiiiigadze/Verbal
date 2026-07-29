//
//  AccountView.swift
//  Verbal
//
//  Settings → (profile row). The user's profile: read-only account identity
//  from Google up top, then the editable business details that appear on the
//  quotes they send. Quote defaults live on their own screen.
//

import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var businessName = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var taxNumber = ""

    /// The full row as loaded, so saving our subset preserves quote defaults.
    @State private var loaded = BusinessProfile.empty
    @State private var isLoading = true
    @State private var isSaving = false
    @FocusState private var keyboardShown: Bool

    private var isDirty: Bool {
        [businessName, phone, address, taxNumber] != loadedIdentity
    }

    private var loadedIdentity: [String] {
        [loaded.businessName ?? "", loaded.phone ?? "",
         loaded.address ?? "", loaded.taxNumber ?? ""]
    }

    var body: some View {
        ZStack {
            Color(.homeBackground).ignoresSafeArea()
            Form {
            // Read-only identity from the Google account.
            Section {
                VStack(spacing: 12) {
                    AvatarView(image: session.avatarImage,
                               urlString: session.profile?.avatarUrl, size: 88)
                    if let name = session.profile?.fullName, !name.isEmpty {
                        Text(name).font(.title3.bold()).foregroundStyle(Color(.mainText))
                    }
                    if let email = session.email, !email.isEmpty {
                        Text(email).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Business name", text: $businessName)
                    .focused($keyboardShown)
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                    .focused($keyboardShown)
                TextField("Address", text: $address, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($keyboardShown)
                TextField("Tax / VAT number", text: $taxNumber)
                    .focused($keyboardShown)
            } header: {
                Text("Business")
            } footer: {
                Text("Appears on the quotes you send to customers.")
            }
            .listRowBackground(Color(.surface))
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Profile")
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
                        Text("Save").fontWeight(.semibold).foregroundStyle(.white)
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(Color(.royalBlue600))
                .disabled(isLoading || isSaving || !isDirty)
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyboardShown = false }.fontWeight(.semibold)
            }
        }
        .task { await load() }
        }
    }

    private func load() async {
        // Seed instantly from the profile preloaded at bootstrap; only hit the
        // network if it wasn't cached (e.g. first run).
        if let cached = session.businessProfile {
            loaded = cached
        } else if let fetched = try? await BusinessService.fetch() {
            loaded = fetched
        }
        businessName = loaded.businessName ?? ""
        phone = loaded.phone ?? ""
        address = loaded.address ?? ""
        taxNumber = loaded.taxNumber ?? ""
        isLoading = false
    }

    private func save() {
        isSaving = true
        var profile = loaded
        profile.businessName = trimmedOrNil(businessName)
        profile.phone = trimmedOrNil(phone)
        profile.address = trimmedOrNil(address)
        profile.taxNumber = trimmedOrNil(taxNumber)
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
