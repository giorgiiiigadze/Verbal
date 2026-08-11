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
    @State private var email = ""
    @State private var address = ""
    @State private var taxNumber = ""

    /// The full row as loaded, so saving our subset preserves quote defaults.
    @State private var loaded = BusinessProfile.empty
    @State private var isLoading = true
    @State private var isSaving = false
    @FocusState private var keyboardShown: Bool

    @State private var toast: Toast?

    private var isDirty: Bool {
        [businessName, phone, email, address, taxNumber] != loadedIdentity
    }

    private var loadedIdentity: [String] {
        [loaded.businessName ?? "", loaded.phone ?? "", loaded.email ?? "",
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
                    // Placeholder is the account address, because that is what
                    // gets used when this is blank — leaving it empty should
                    // not be a mystery about what the customer will see.
                    TextField(session.email ?? "Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($keyboardShown)
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($keyboardShown)
                    TextField("Tax / VAT number", text: $taxNumber)
                        .focused($keyboardShown)
                } header: {
                    Text("Business")
                } footer: {
                    Text("Appears on the quotes you send to customers. Leave the email blank to use the one you signed in with.")
                }
                .listRowBackground(Color(.cardSurface))

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
            // Save takes the gear's place while there are edits to keep, rather
            // than appearing beside it. Two trailing controls at once asks the
            // user to aim, and the one they'd be aiming past leaves the screen —
            // this is the moment when tapping the gear loses their typing.
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else if isDirty {
                    // The same button the quote screen uses to send work out:
                    // this is the one action on the screen that matters, and it
                    // should look like it does elsewhere.
                    Button {
                        save()
                    } label: {
                        Text("Save")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color(.royalBlue600))
                    .disabled(isLoading)
                } else {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyboardShown = false }.fontWeight(.semibold)
            }
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
        email = loaded.email ?? ""
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
        profile.email = trimmedOrNil(email)
        profile.address = trimmedOrNil(address)
        profile.taxNumber = trimmedOrNil(taxNumber)
        Task {
            defer { isSaving = false }
            do {
                try await BusinessService.save(profile)
            } catch {
                // `loaded` is deliberately left alone: the fields stay dirty, so
                // Save stays on screen to be tried again. Reporting success here
                // would send the next quote out with no business name on it and
                // the user believing they had fixed that.
                toast = Toast(style: .error, message: "Couldn't save business details")
                return
            }
            session.cacheBusinessProfile(profile)
            loaded = profile
            keyboardShown = false
            toast = Toast(style: .success, message: "Business details saved")
        }
    }

    private func trimmedOrNil(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
