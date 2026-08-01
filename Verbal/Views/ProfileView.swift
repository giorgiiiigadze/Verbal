//
//  ProfileView.swift
//  Verbal
//
//  The Profile tab: account identity from Google, the business details printed
//  on the quotes you send, and account deletion — all on one screen. Quote
//  defaults and currency live behind the gear, in Settings.
//

import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

    @State private var showSettings = false

    @State private var businessName = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var taxNumber = ""

    /// The full row as loaded, so saving our subset preserves quote defaults.
    @State private var loaded = BusinessProfile.empty
    @State private var isLoading = true
    @State private var isSaving = false
    @FocusState private var keyboardShown: Bool

    @State private var toast: Toast?
    @State private var showSignOutConfirmation = false

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

                Section {
                    Button("Sign out", role: .destructive) {
                        showSignOutConfirmation = true
                    }
                }
                .listRowBackground(Color(.surface))
            }
            .scrollContentBackground(.hidden)
            .disabled(isLoading)
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else if isDirty {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isLoading)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyboardShown = false }.fontWeight(.semibold)
            }
        }
        .alert("Sign out of Verbal?", isPresented: $showSignOutConfirmation) {
            Button("Sign out", role: .destructive) {
                Task { try? await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your quotes stay safe — you'll just need to sign in again.")
        }
        .toast($toast)
        .task { await load() }
    }

    // MARK: - Data

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

    /// Saves in place rather than dismissing — this is a tab, not a pushed
    /// screen, so there's nowhere to go back to.
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
            loaded = profile
            isSaving = false
            keyboardShown = false
            toast = Toast(style: .success, message: "Business details saved")
        }
    }

    private func trimmedOrNil(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
