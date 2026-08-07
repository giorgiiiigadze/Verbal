//
//  ProfileView.swift
//  Verbal
//
//  The Profile tab: account identity from Google, the business details printed
//  on the quotes you send, and account deletion — all on one screen. Quote
//  defaults and currency live behind the gear, in Settings.
//

import SwiftUI
import PhotosUI

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
    @State private var showSignOutConfirmation = false
    /// The logo saves on its own, the moment it's picked — it isn't part of the
    /// dirty-fields Save, because choosing a picture already reads as a decision
    /// and nobody expects to confirm it twice.
    @State private var pickedLogo: PhotosPickerItem?
    @State private var isUploadingLogo = false

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
                    logoRow
                    if session.businessLogo != nil {
                        Button("Remove logo", role: .destructive) { removeLogo() }
                            .disabled(isUploadingLogo)
                    }
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
        .alert("Sign out of Verbal?", isPresented: $showSignOutConfirmation) {
            Button("Sign out", role: .destructive) {
                Task { try? await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your quotes stay safe — you'll just need to sign in again.")
        }
        .toast($toast)
        .onChange(of: pickedLogo) { _, item in
            guard let item else { return }
            Task { await applyLogo(item) }
        }
        .task { await load() }
    }

    // MARK: - Logo

    /// The whole row is the picker. A separate "Remove logo" button sits under
    /// it rather than a small × inside it: two targets in one row means the
    /// user has to aim, and one of them deletes their letterhead.
    private var logoRow: some View {
        // Read out here, not inside the picker's label. That closure is
        // nonisolated, so touching the store from within it is an error under
        // Swift 6 — the same trap that made the background cache read hop back
        // onto the main thread.
        let logo = session.businessLogo
        // No `photoLibrary: .shared()`. That runs the picker inside the app and
        // makes iOS ask for library access first — "Verbal can only access the
        // items you select", a privacy question raised over choosing a logo.
        // The default picker runs out of process: the app is handed the one
        // image and never gets access to the library at all.
        return PhotosPicker(selection: $pickedLogo, matching: .images) {
            HStack(spacing: 14) {
                logoTile(logo)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logo")
                        .foregroundStyle(Color(.mainText))
                    Text(logo == nil
                         ? "Printed at the top of every quote"
                         : "Tap to replace")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }
            .padding(.vertical, 4)
        }
        .disabled(isUploadingLogo)
    }

    /// Shows the mark on white, at the size and on the ground it will print on,
    /// so what's on this screen is what the customer receives.
    private func logoTile(_ logo: UIImage?) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(.cardSurface))
            .frame(width: 58, height: 58)
            .overlay {
                if let logo {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .padding(7)
                        .opacity(isUploadingLogo ? 0.3 : 1)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color(.blueAccentText))
                }
            }
            .overlay {
                if isUploadingLogo { ProgressView() }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
    }

    /// Shown immediately, uploaded after. The picture is already on screen in
    /// the picker when they tap it; making the row wait for a round trip before
    /// agreeing would be the app doubting a choice the user has made.
    private func applyLogo(_ item: PhotosPickerItem) async {
        isUploadingLogo = true
        defer { isUploadingLogo = false; pickedLogo = nil }

        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            toast = Toast(style: .error, message: "Couldn't read that image")
            return
        }

        let previousURL = loaded.logoUrl
        let previousImage = session.businessLogo
        session.cacheBusinessLogo(image)

        var profile = loaded
        do {
            profile.logoUrl = try await LogoService.upload(image)
            try await BusinessService.save(profile)
        } catch {
            // Put back exactly what was there, including the case where that
            // was nothing. A logo that looks saved and isn't goes out on the
            // next quote as a blank letterhead.
            session.cacheBusinessLogo(previousImage)
            toast = Toast(style: .error, message: "Couldn't save your logo")
            return
        }
        loaded = profile
        session.cacheBusinessProfile(profile)
        // Only once the new one is safely referenced. Deleting first would risk
        // a failed upload leaving the user with no logo at all.
        await LogoService.removeStored(at: previousURL)
        toast = Toast(style: .success, message: "Logo saved")
    }

    private func removeLogo() {
        let previousURL = loaded.logoUrl
        let previousImage = session.businessLogo
        session.cacheBusinessLogo(nil)
        var profile = loaded
        profile.logoUrl = nil
        Task {
            do {
                try await BusinessService.save(profile)
            } catch {
                session.cacheBusinessLogo(previousImage)
                toast = Toast(style: .error, message: "Couldn't remove your logo")
                return
            }
            loaded = profile
            session.cacheBusinessProfile(profile)
            await LogoService.removeStored(at: previousURL)
            toast = Toast(style: .success, message: "Logo removed")
        }
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
