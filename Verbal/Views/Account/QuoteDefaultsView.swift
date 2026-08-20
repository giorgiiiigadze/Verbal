//
//  QuoteDefaultsView.swift
//  Verbal
//
//  Settings → Quote defaults. Values that pre-fill every new quote.
//

import SwiftUI
import PhotosUI

struct QuoteDefaultsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var pickedLogo: PhotosPickerItem?
    @State private var isUploadingLogo = false
    @State private var toast: Toast?

    @State private var validityDays = 14
    @State private var taxRate = ""
    @State private var terms = ""
    @State private var notes = ""
    @State private var numberPrefix = ""
    @State private var numberStart = ""

    @State private var loaded = BusinessProfile.empty
    @State private var isLoading = true
    @State private var isSaving = false

    @State private var saveFailed = false
    @State private var loadFailed = false

    private enum Field: Hashable {
        case numberPrefix, numberStart, taxRate, terms, notes
    }
    @FocusState private var focus: Field?

    // MARK: - Validation

    private var taxRateValue: Double {
        Double(
            taxRate
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
        ) ?? 0
    }

    private var isTaxRateValid: Bool {
        let trimmed = taxRate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return true
        }

        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else {
            return false
        }

        return (0...100).contains(value)
    }

    private var numberStartValue: Int {
        max(
            Int(numberStart.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1,
            1
        )
    }

    private var isNumberStartValid: Bool {
        let trimmed = numberStart.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            return true
        }

        guard let value = Int(trimmed) else {
            return false
        }

        return value >= 1
    }

    private var trimmedPrefix: String {
        numberPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var numberPreview: String {
        let padded = String(format: "%04d", numberStartValue)
        return trimmedPrefix.isEmpty ? padded : trimmedPrefix + padded
    }

    private var isInputValid: Bool {
        isTaxRateValid && isNumberStartValid
    }

    private var isDirty: Bool {
        validityDays != loaded.defaultValidityDays
            || taxRateValue != loaded.defaultTaxRate
            || terms.trimmedOrNil != loaded.defaultTerms
            || notes.trimmedOrNil != loaded.defaultNotes
            || trimmedPrefix.trimmedOrNil != loaded.quoteNumberPrefix
            || numberStartValue != loaded.quoteNumberStart
    }

    private var canSave: Bool {
        !isLoading
            && !loadFailed
            && !isSaving
            && isDirty
            && isInputValid
    }

    private var taxRateError: String? {
        guard !isTaxRateValid else { return nil }
        return "Enter a tax rate from 0% to 100%."
    }

    private var numberStartError: String? {
        guard !isNumberStartValid else { return nil }
        return "Enter a whole number of 1 or higher."
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.homeBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Letterhead")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        letterheadPreview
                        logoControls

                        Text("The top of every quote you send. Your business name and contact details come from Profile.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quote numbers")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        field(
                            "Prefix",
                            placeholder: "None",
                            text: $numberPrefix,
                            focus: .numberPrefix
                        )
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                        field(
                            "Start at",
                            placeholder: "1",
                            text: $numberStart,
                            focus: .numberStart
                        )
                        .keyboardType(.numberPad)
                        .font(.body.monospacedDigit())

                        VStack(alignment: .leading, spacing: 7) {
                            Text("Next quote")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            Text(numberPreview)
                                .font(.body.monospacedDigit())
                                .foregroundStyle(Color(.mainText))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .background(Color(.cardSurface))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color(.separator), lineWidth: 1)
                                }
                        }

                        if let numberStartError {
                            Text(numberStartError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Text("Start only applies while your numbering is still below it. Quotes already issued keep their numbers. Changing the prefix relabels every quote that uses the shared prefix.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Validity")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        Stepper(
                            "Valid for \(validityDays) day\(validityDays == 1 ? "" : "s")",
                            value: $validityDays,
                            in: 1...365
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .background(Color(.cardSurface))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color(.separator), lineWidth: 1)
                        }

                        Text("How long a new quote stays valid for.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tax")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        percentField(
                            "Tax rate",
                            placeholder: "0",
                            text: $taxRate,
                            focus: .taxRate
                        )
                        .keyboardType(.decimalPad)

                        if let taxRateError {
                            Text(taxRateError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }

                        Text("Added to new quotes and shown as a separate line on the PDF. Leave blank or 0 if you're not tax registered.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Terms & conditions")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        field(
                            "Terms",
                            placeholder: "Standard terms shown on every quote",
                            text: $terms,
                            focus: .terms,
                            axis: .vertical,
                            lineLimit: 3...8
                        )
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Notes / footer")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        field(
                            "Note",
                            placeholder: "A note added to the bottom of each quote",
                            text: $notes,
                            focus: .notes,
                            axis: .vertical,
                            lineLimit: 2...6
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Quote defaults")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isLoading)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            save()
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()

                    Button {
                        focus = nil
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Hide keyboard")
                }
            }
            .task {
                await load()
            }
            .onChange(of: pickedLogo) { _, item in
                guard let item else { return }

                Task {
                    await applyLogo(item)
                }
            }
            .toast($toast)
            .alert(
                "Couldn't save your defaults",
                isPresented: $saveFailed
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    "Check your connection and tap Save again. Your changes are still here."
                )
            }
            .alert(
                "Couldn't load your quote defaults",
                isPresented: $loadFailed
            ) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(
                    "Your existing settings couldn't be loaded, so saving has been disabled to prevent replacing them accidentally."
                )
            }
        }
    }

    private func field(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        focus field: Field,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int> = 1...1
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(focus == field ? Color(.blueAccentText) : .secondary)

            TextField(placeholder, text: text, axis: axis)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(Color(.mainText))
                .tint(Color(.blueAccentText))
                .lineLimit(lineLimit)
                .focused($focus, equals: field)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(Color(.cardSurface))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            focus == field ? Color(.blueAccentText) : Color(.separator),
                            lineWidth: 1
                        )
                }
        }
    }

    private func percentField(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        focus field: Field
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(focus == field ? Color(.blueAccentText) : .secondary)

            HStack(spacing: 6) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(Color(.mainText))
                    .tint(Color(.blueAccentText))
                    .focused($focus, equals: field)

                Text("%")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(Color(.cardSurface))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        focus == field ? Color(.blueAccentText) : Color(.separator),
                        lineWidth: 1
                    )
            }
        }
    }

    // MARK: - Letterhead

    private var logoControls: some View {
        let hasLogo = session.businessLogo != nil

        return HStack(spacing: 10) {
            PhotosPicker(
                selection: $pickedLogo,
                matching: .images
            ) {
                glassLabel(
                    hasLogo ? "Replace" : "Add logo",
                    systemImage: "photo",
                    tint: Color(.blueAccentText)
                )
            }
            .disabled(isUploadingLogo)

            if hasLogo {
                Button {
                    removeLogo()
                } label: {
                    glassLabel(
                        "Remove",
                        systemImage: "trash",
                        tint: .red
                    )
                }
                .buttonStyle(.plain)
                .disabled(isUploadingLogo)
            }
        }
    }

    private func glassLabel(
        _ title: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .glassEffect(in: .capsule)
    }

    private var letterheadPreview: some View {
        let logo = session.businessLogo
        let profile = session.businessProfile

        let businessName = profile?.businessName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayBusinessName = if let businessName, !businessName.isEmpty {
            businessName
        } else {
            "Your business name"
        }

        let contact = [
            profile?.phone,
            profile?.email,
            profile?.address
        ]
        .compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter {
            !$0.isEmpty
        }

        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                if let logo {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxWidth: 120,
                            maxHeight: 42,
                            alignment: .leading
                        )
                        .padding(.bottom, 3)
                        .opacity(isUploadingLogo ? 0.3 : 1)
                } else {
                    RoundedRectangle(
                        cornerRadius: 6,
                        style: .continuous
                    )
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: [4, 4]
                        )
                    )
                    .foregroundStyle(.black.opacity(0.18))
                    .frame(width: 76, height: 42)
                    .overlay {
                        Image(systemName: "photo")
                            .font(
                                .system(
                                    size: 15,
                                    weight: .light
                                )
                            )
                            .foregroundStyle(.black.opacity(0.3))
                    }
                    .padding(.bottom, 3)
                }

                Text(displayBusinessName)
                .font(.robotoSlab(16, relativeTo: .headline))
                .foregroundStyle(
                    businessName?.isEmpty == false
                        ? .black
                        : .black.opacity(0.35)
                )

                ForEach(contact, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 8))
                        .foregroundStyle(.black.opacity(0.6))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            Text("QUOTE")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.royalBlue800))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            .white,
            in: RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
        )
        .overlay {
            if isUploadingLogo {
                ProgressView()
            }
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: 14,
                style: .continuous
            )
            .strokeBorder(
                Color(.separator),
                lineWidth: 0.5
            )
        }
    }

    // MARK: - Logo

    private func applyLogo(
        _ item: PhotosPickerItem
    ) async {
        isUploadingLogo = true

        defer {
            isUploadingLogo = false
            pickedLogo = nil
        }

        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data)
        else {
            toast = Toast(
                style: .error,
                message: "Couldn't read that image"
            )
            return
        }

        let previousURL = loaded.logoUrl
        let previousImage = session.businessLogo

        session.cacheBusinessLogo(image)

        var profile = loaded
        var uploadedURL: String?

        do {
            let newURL = try await LogoService.upload(image)
            uploadedURL = newURL

            profile.logoUrl = newURL

            try await BusinessService.save(profile)
        } catch {
            session.cacheBusinessLogo(previousImage)

            // Prevent an orphaned uploaded logo if the database save failed.
            if let uploadedURL {
                await LogoService.removeStored(at: uploadedURL)
            }

            toast = Toast(
                style: .error,
                message: "Couldn't save your logo"
            )
            return
        }

        loaded = profile
        session.cacheBusinessProfile(profile)

        // Only remove the old logo after the new one is safely referenced.
        await LogoService.removeStored(at: previousURL)

        toast = Toast(
            style: .success,
            message: "Logo saved"
        )
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

                toast = Toast(
                    style: .error,
                    message: "Couldn't remove your logo"
                )
                return
            }

            loaded = profile
            session.cacheBusinessProfile(profile)

            await LogoService.removeStored(at: previousURL)

            toast = Toast(
                style: .success,
                message: "Logo removed"
            )
        }
    }

    // MARK: - Loading

    private func trimmedRate(_ rate: Double) -> String {
        rate == rate.rounded()
            ? String(Int(rate))
            : String(rate)
    }

    private func load() async {
        if let cached = session.businessProfile {
            loaded = cached
        } else if let fetched = try? await BusinessService.fetch() {
            loaded = fetched
        } else {
            isLoading = false
            loadFailed = true
            return
        }

        validityDays = loaded.defaultValidityDays

        taxRate = loaded.defaultTaxRate == 0
            ? ""
            : trimmedRate(loaded.defaultTaxRate)

        terms = loaded.defaultTerms ?? ""
        notes = loaded.defaultNotes ?? ""
        numberPrefix = loaded.quoteNumberPrefix ?? ""

        numberStart = loaded.quoteNumberStart <= 1
            ? ""
            : String(loaded.quoteNumberStart)

        isLoading = false
    }

    // MARK: - Saving

    private func save() {
        guard canSave else { return }

        focus = nil
        isSaving = true

        var profile = loaded

        profile.defaultValidityDays = validityDays
        profile.defaultTaxRate = taxRateValue
        profile.defaultTerms = terms.trimmedOrNil
        profile.defaultNotes = notes.trimmedOrNil
        profile.quoteNumberPrefix = numberPrefix.trimmedOrNil
        profile.quoteNumberStart = numberStartValue

        Task {
            defer {
                isSaving = false
            }

            do {
                try await BusinessService.save(profile)
            } catch {
                saveFailed = true
                return
            }

            session.cacheBusinessProfile(profile)
            loaded = profile

            dismiss()
        }
    }
}
