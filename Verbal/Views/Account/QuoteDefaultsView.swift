//
//  QuoteDefaultsView.swift
//  Verbal
//
//  Settings → Quote defaults. Values that pre-fill every new quote: how long
//  it's valid, plus standard terms and notes. Saved onto the same
//  business_profiles row as the profile identity.
//

import SwiftUI
import PhotosUI

struct QuoteDefaultsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    /// The logo saves the moment it's picked, on its own — it isn't part of the
    /// Save button, because choosing a picture already reads as a decision and
    /// nobody expects to confirm it twice.
    @State private var pickedLogo: PhotosPickerItem?
    @State private var isUploadingLogo = false
    @State private var toast: Toast?

    @State private var validityDays = 14
    /// Percentage as typed, e.g. "20". Empty means not tax registered.
    @State private var taxRate = ""
    @State private var terms = ""
    @State private var notes = ""

    /// The full row as loaded, so saving our subset preserves the identity fields.
    @State private var loaded = BusinessProfile.empty
    @State private var isLoading = true
    @State private var isSaving = false
    /// Set when the write failed, so the screen stays put and says so.
    @State private var saveFailed = false
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
                // One row holding the whole block, on a clear background: as
                // separate Form rows the controls were divided from the page
                // they act on, and ruled off from each other as though they
                // were unrelated settings.
                VStack(spacing: 12) {
                    letterheadPreview
                    logoControls
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            } header: {
                Text("Letterhead")
            } footer: {
                Text("The top of every quote you send. Your business name and contact details come from Profile.")
            }

            Section {
                Stepper("Valid for \(validityDays) day\(validityDays == 1 ? "" : "s")",
                        value: $validityDays, in: 1...365)
            } footer: {
                Text("How long a new quote stays valid for.")
            }
            .listRowBackground(Color(.cardSurface))

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
            .listRowBackground(Color(.cardSurface))

            Section("Terms & conditions") {
                TextField("Standard terms shown on every quote", text: $terms, axis: .vertical)
                    .lineLimit(3...8)
                    .focused($keyboardShown)
            }
            .listRowBackground(Color(.cardSurface))

            Section("Notes / footer") {
                TextField("A note added to the bottom of each quote", text: $notes, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($keyboardShown)
            }
            .listRowBackground(Color(.cardSurface))
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
        .onChange(of: pickedLogo) { _, item in
            guard let item else { return }
            Task { await applyLogo(item) }
        }
        .toast($toast)
        .alert("Couldn't save your defaults", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and tap Save again. Your changes are still here.")
        }
        }
    }

    // MARK: - Letterhead

    /// Glass, like the toast and the Share button — the app's own material
    /// rather than a Form row pretending to be a control. Side by side because
    /// they are two answers to the same question, and Remove only exists once
    /// there is something to remove, so the pair never has a dead half.
    private var logoControls: some View {
        // Read before the closures: a picker's label is a Sendable closure and
        // can't reach the main-actor store from inside it.
        let hasLogo = session.businessLogo != nil
        return HStack(spacing: 10) {
            PhotosPicker(selection: $pickedLogo, matching: .images) {
                glassLabel(hasLogo ? "Replace" : "Add logo",
                           systemImage: "photo",
                           tint: Color(.blueAccentText))
            }
            .disabled(isUploadingLogo)

            if hasLogo {
                Button { removeLogo() } label: {
                    glassLabel("Remove", systemImage: "trash", tint: .red)
                }
                .buttonStyle(.plain)
                .disabled(isUploadingLogo)
            }
        }
        .padding(.horizontal, 16)
    }

    private func glassLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .glassEffect(in: .capsule)
    }

    /// The header of the printed quote, not a settings row with a thumbnail in
    /// it. A logo is only ever seen next to the business name and contact
    /// lines, and this is the one screen where the user can be shown that
    /// arrangement instead of asked to imagine it.
    ///
    /// White regardless of the app's appearance, because paper is. The same
    /// reason the text on it is set in black rather than the theme's ink.
    private var letterheadPreview: some View {
        let logo = session.businessLogo
        let profile = session.businessProfile
        let name = profile?.businessName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = [profile?.phone, profile?.email, profile?.address]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                if let logo {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 120, maxHeight: 42, alignment: .leading)
                        .padding(.bottom, 3)
                        .opacity(isUploadingLogo ? 0.3 : 1)
                } else {
                    // Holds the space the logo will occupy, so adding one
                    // rearranges nothing — and shows its size before committing.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.black.opacity(0.18))
                        .frame(width: 76, height: 42)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 15, weight: .light))
                                .foregroundStyle(.black.opacity(0.3))
                        }
                        .padding(.bottom, 3)
                }
                Text(name?.isEmpty == false ? name! : "Your business name")
                    .font(.robotoSlab(16, relativeTo: .headline))
                    .foregroundStyle(name?.isEmpty == false ? .black : .black.opacity(0.35))
                ForEach(contact, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 8))
                        .foregroundStyle(.black.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            // The other half of the printed header, so the preview reads as a
            // page rather than as a picture of a logo.
            Text("QUOTE")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.royalBlue800))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
        .overlay {
            if isUploadingLogo { ProgressView() }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
                .padding(.horizontal, 16)
        )
    }

    /// Shown immediately, uploaded after. The picture is already on screen in
    /// the picker when they tap it; making the preview wait for a round trip
    /// before agreeing would be the app doubting a choice the user has made.
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
            defer { isSaving = false }
            do {
                try await BusinessService.save(profile)
            } catch {
                // Closing on a failed write is worse here than anywhere else in
                // the app: the tax rate set on this screen is copied onto every
                // quote made afterwards, so a save that quietly didn't happen
                // means months of quotes priced without VAT on them.
                saveFailed = true
                return
            }
            session.cacheBusinessProfile(profile)
            loaded = profile
            dismiss()
        }
    }

    private func trimmedOrNil(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
