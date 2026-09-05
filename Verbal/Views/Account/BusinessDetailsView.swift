//
//  BusinessDetailsView.swift
//  Verbal
//
//  The business details printed on the quotes you send, and the trade Verbal
//  reads your jobs against. Pushed from the Account tab; it was that tab itself
//  until the settings behind its gear came up to the surface.
//
//  A simple form with labelled rounded fields and quiet section headings.
//

import SwiftUI

struct BusinessDetailsView: View {
    @Environment(SessionStore.self) private var session

    @State private var businessName = ""
    @State private var trade = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var address = ""
    @State private var taxNumber = ""

    /// The full row as loaded, so saving our subset preserves quote defaults.
    @State private var loaded = BusinessProfile.empty
    @State private var isLoading = true
    @State private var isSaving = false

    private enum Field: Hashable {
        case businessName, trade, phone, email, address, taxNumber
    }
    @FocusState private var focus: Field?

    @State private var toast: Toast?

    private var isDirty: Bool {
        [businessName, trade, phone, email, address, taxNumber] != loadedIdentity
    }

    private var canSave: Bool {
        !isLoading && !isSaving && isDirty
    }

    private var loadedIdentity: [String] {
        [loaded.businessName ?? "", loaded.trade ?? "", loaded.phone ?? "",
         loaded.email ?? "", loaded.address ?? "", loaded.taxNumber ?? ""]
    }

    private var accountName: String {
        if let name = session.profile?.fullName?.trimmedOrNil { return name }
        if let username = session.profile?.username?.trimmedOrNil { return username }
        return "Your profile"
    }

    private var accountEmail: String? {
        session.email?.trimmedOrNil
    }

    var body: some View {
        ZStack {
            Color(.accountBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    accountProfile

                    Text("These details appear on every quote you send and help Verbal understand your work.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your business information")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        field(
                            "Business name",
                            placeholder: "Your business name",
                            text: $businessName,
                            focus: .businessName,
                            isRequired: true
                        )
                        .textInputAutocapitalization(.words)

                        field(
                            "Phone",
                            placeholder: "Phone number",
                            text: $phone,
                            focus: .phone
                        )
                        .keyboardType(.phonePad)

                        field(
                            "Email",
                            placeholder: session.email ?? "Email",
                            text: $email,
                            focus: .email
                        )
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        field(
                            "Address",
                            placeholder: "Street, town, postcode",
                            text: $address,
                            focus: .address,
                            axis: .vertical,
                            lineLimit: 2...4
                        )
                        .textInputAutocapitalization(.words)

                        field(
                            "Tax / VAT number",
                            placeholder: "None",
                            text: $taxNumber,
                            focus: .taxNumber
                        )
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Quote intelligence")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color(.mainText))

                        field(
                            "Trade",
                            placeholder: "Electrician, plumber, builder...",
                            text: $trade,
                            focus: .trade
                        )
                        .textInputAutocapitalization(.words)

                        Text("Used to help Verbal understand the jobs you describe. It isn't printed on your quotes.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(isLoading)
        }
        .navigationTitle("Business details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isSaving {
                    ProgressView()
                } else if canSave {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
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
        .toast($toast)
        .task { await load() }
    }

    private var accountProfile: some View {
        VStack(alignment: .leading, spacing: 14) {
            AvatarView(image: session.avatarImage,
                       urlString: session.profile?.avatarUrl,
                       size: 64)

            VStack(alignment: .leading, spacing: 3) {
                Text(accountName)
                    .font(.robotoSlab(22, relativeTo: .title3))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)

                if let accountEmail {
                    Text(accountEmail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        }
    }

    private func field(
        _ label: String,
        placeholder: String,
        text: Binding<String>,
        focus field: Field,
        isRequired: Bool = false,
        axis: Axis = .horizontal,
        lineLimit: ClosedRange<Int> = 1...1
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label + (isRequired ? " *" : ""))
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
        trade = loaded.trade ?? ""
        phone = loaded.phone ?? ""
        email = loaded.email ?? ""
        address = loaded.address ?? ""
        taxNumber = loaded.taxNumber ?? ""
        isLoading = false
    }

    /// Saves in place rather than popping back. The toast is the receipt, and a
    /// screen that leaves the moment you tap Save takes its own confirmation
    /// with it — on the one screen where a silent failure means the next quote
    /// goes out with no business name on it.
    private func save() {
        guard canSave else { return }

        focus = nil
        isSaving = true
        var profile = loaded
        profile.businessName = businessName.trimmedOrNil
        profile.trade = trade.trimmedOrNil
        profile.phone = phone.trimmedOrNil
        profile.email = email.trimmedOrNil
        profile.address = address.trimmedOrNil
        profile.taxNumber = taxNumber.trimmedOrNil
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
            focus = nil
            toast = Toast(style: .success, message: "Business details saved")
        }
    }
}
