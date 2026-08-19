//
//  ProfileView.swift
//  Verbal
//
//  The Profile tab: who is signed in, and the business details printed on the
//  quotes they send. Quote defaults, currency and the account doors live behind
//  the gear, in Settings.
//
//  Drawn by hand rather than as a stock `Form`, for the same reason Home and
//  the client page are: a grouped iOS list sitting next to those screens reads
//  as a different app, and it was the last of the three settings screens still
//  doing it. The page is built from the parts they already use — a heading with
//  a face beside it, a quiet section label, one card carrying the content, and
//  a line of plain text under it saying what the card is for.
//

import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session

    @State private var showSettings = false

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

    /// Which field holds the keyboard.
    ///
    /// Named rather than a single bool because the whole row is tappable: a
    /// label and the space beside it should reach the field underneath them
    /// instead of being dead ground around a one-line target.
    private enum Field: Hashable {
        case businessName, trade, phone, email, address, taxNumber
    }
    @FocusState private var focus: Field?

    @State private var toast: Toast?

    private var isDirty: Bool {
        [businessName, trade, phone, email, address, taxNumber] != loadedIdentity
    }

    private var loadedIdentity: [String] {
        [loaded.businessName ?? "", loaded.trade ?? "", loaded.phone ?? "",
         loaded.email ?? "", loaded.address ?? "", loaded.taxNumber ?? ""]
    }

    /// The page's heading. Their name where the account has one, and otherwise
    /// the business — never a blank line where a title should be.
    private var displayName: String {
        if let name = session.profile?.fullName?.trimmedOrNil { return name }
        if let name = businessName.trimmedOrNil { return name }
        return "Your profile"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                section("Business",
                        footer: "Printed at the top of every quote you send, and how a client reaches you to say yes. Leave the email blank to use the one you signed in with.") {
                    fieldRow("Business name", placeholder: "Your business name",
                             text: $businessName, field: .businessName)
                        .textInputAutocapitalization(.words)
                    rowDivider
                    fieldRow("Phone", placeholder: "Phone number",
                             text: $phone, field: .phone)
                        .keyboardType(.phonePad)
                    rowDivider
                    // Placeholder is the account address, because that is what
                    // gets used when this is blank — leaving it empty should
                    // not be a mystery about what the customer will see.
                    fieldRow("Email", placeholder: session.email ?? "Email",
                             text: $email, field: .email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    rowDivider
                    fieldRow("Address", placeholder: "Street, town, postcode",
                             text: $address, field: .address, multiline: true)
                        .textInputAutocapitalization(.words)
                    rowDivider
                    fieldRow("Tax / VAT number", placeholder: "None",
                             text: $taxNumber, field: .taxNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                // Its own section rather than a sixth row above: the trade is
                // the only thing on this screen the customer never sees, and
                // filing it under a card that promises "printed on every quote"
                // would be a lie about where it goes. It was asked for once at
                // onboarding and then had nowhere to be corrected — a typo
                // there quietly mislead every extraction since.
                section("Trade",
                        footer: "What you do, in a word. Verbal reads it to make sense of the jobs you describe out loud. It isn't printed on your quotes.") {
                    // No row label: the card holds one field and the section
                    // heading above it already names that field. Labelling it
                    // again would print "Trade" twice, two lines apart.
                    fieldRow(nil, placeholder: "Electrician, plumber, builder…",
                             text: $trade, field: .trade)
                        .textInputAutocapitalization(.words)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 40)
            .disabled(isLoading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.homeBackground))
        // The name is the page's own heading, in the size it deserves — the
        // same arrangement the client page uses. A bar title would say "Profile"
        // over a screen that has already introduced itself.
        .navigationTitle("")
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
                    .accessibilityLabel("Settings")
                }
            }
            // The glyph rather than "Done", which iOS draws as a round glass
            // button in the corner above the keyboard. It says what it does —
            // put the keyboard away — where "Done" reads as a commitment, and
            // on this screen the thing that commits is Save, up in the bar.
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

    // MARK: - Header

    /// Face, name, account address — laid out exactly as a client's page lays
    /// out theirs, because this is the same kind of heading: one person, and
    /// the one line worth knowing about them.
    private var header: some View {
        HStack(spacing: 14) {
            AvatarView(image: session.avatarImage,
                       urlString: session.profile?.avatarUrl, size: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.robotoSlab(28, relativeTo: .title))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let email = session.email, !email.isEmpty {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    // MARK: - Section scaffolding

    /// A label, a card, and a sentence saying what the card is for.
    ///
    /// The three parts a `Form` section has, set the way the rest of the app
    /// sets them: the label in the same weight Home gives its date headings,
    /// and the footer as ordinary text under the card rather than ruled-off
    /// grey type.
    private func section<Content: View>(_ title: String,
                                        footer: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) { content() }
                .background(Color(.cardSurface), in: Self.cardShape)
                .overlay(Self.cardShape.strokeBorder(Color(.separator), lineWidth: 0.5))
            Text(footer)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
                .padding(.top, 2)
        }
    }

    /// The same radius the quote and rate cards carry.
    private static let cardShape = RoundedRectangle(cornerRadius: 18, style: .continuous)

    /// Inset from the left so it starts under the labels, which keeps the rows
    /// reading as one card rather than a stack of separate ones.
    private var rowDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: 0.5)
            .padding(.leading, 16)
    }

    // MARK: - Rows

    /// One editable detail: its name above, the value in it below.
    ///
    /// Stacked rather than the label-left / value-right of a settings row,
    /// because two of these are addresses. Right-aligned multi-line text under
    /// a left-aligned label reads as a column of ragged fragments, and the
    /// address is the field most often wrong on a quote.
    ///
    /// The label carries the focus: it turns blue while the keyboard is in the
    /// field beneath it, which is enough to mark where you are typing without
    /// drawing a box inside a box. It is optional — a card holding a single
    /// field is already named by its section heading.
    private func fieldRow(_ label: String?,
                          placeholder: String,
                          text: Binding<String>,
                          field: Field,
                          multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(focus == field ? Color(.blueAccentText) : Color.secondary)
            }
            TextField(placeholder, text: text, axis: multiline ? .vertical : .horizontal)
                .textFieldStyle(.plain)
                .font(.callout)
                .lineLimit(multiline ? 4 : 1)
                .foregroundStyle(Color(.mainText))
                .focused($focus, equals: field)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The whole row, not just the line of text, puts the keyboard in it.
        .contentShape(.rect)
        .onTapGesture { focus = field }
        .animation(.easeOut(duration: 0.16), value: focus)
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

    /// Saves in place rather than dismissing — this is a tab, not a pushed
    /// screen, so there's nowhere to go back to.
    private func save() {
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
