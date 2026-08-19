//
//  BusinessDetailsView.swift
//  Verbal
//
//  The business details printed on the quotes you send, and the trade Verbal
//  reads your jobs against. Pushed from the Account tab; it was that tab itself
//  until the settings behind its gear came up to the surface.
//
//  Stock sections, in the app's own card colour on the app's own ground. The
//  rows inside them are not stock: each field keeps its name above the value
//  rather than beside it, because two of these are addresses, and a wrapped
//  address right-aligned against a left-aligned label reads as a column of
//  ragged fragments.
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

    var body: some View {
        List {
            // No section header over the first group: the bar above it already
            // says "Business details", and a heading repeating the word an inch
            // below it is the screen introducing itself twice.
            Section {
                fieldRow("Business name", placeholder: "Your business name",
                         text: $businessName, field: .businessName)
                    .textInputAutocapitalization(.words)
                fieldRow("Phone", placeholder: "Phone number",
                         text: $phone, field: .phone)
                    .keyboardType(.phonePad)
                // Placeholder is the account address, because that is what
                // gets used when this is blank — leaving it empty should
                // not be a mystery about what the customer will see.
                fieldRow("Email", placeholder: session.email ?? "Email",
                         text: $email, field: .email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                fieldRow("Address", placeholder: "Street, town, postcode",
                         text: $address, field: .address, multiline: true)
                    .textInputAutocapitalization(.words)
                fieldRow("Tax / VAT number", placeholder: "None",
                         text: $taxNumber, field: .taxNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } footer: {
                Text("Printed at the top of every quote you send, and how a client reaches you to say yes. Leave the email blank to use the one you signed in with.")
            }
            .listRowBackground(Color(.cardSurface))

            // Its own section rather than a sixth row above: the trade is
            // the only thing on this screen the customer never sees, and
            // filing it under a group that promises "printed on every quote"
            // would be a lie about where it goes. It was asked for once at
            // onboarding and then had nowhere to be corrected — a typo
            // there quietly mislead every extraction since.
            Section {
                // No row label: the section holds one field and the heading
                // above it already names that field. Labelling it again would
                // print "Trade" twice, two lines apart.
                fieldRow(nil, placeholder: "Electrician, plumber, builder…",
                         text: $trade, field: .trade)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Trade")
            } footer: {
                Text("What you do, in a word. Verbal reads it to make sense of the jobs you describe out loud. It isn't printed on your quotes.")
            }
            .listRowBackground(Color(.cardSurface))
        }
        .disabled(isLoading)
        // A list opens with room for a large title, and this one is titled in
        // the bar; the stock inset left the first field floating.
        .contentMargins(.top, 6, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.homeBackground))
        .navigationTitle("Business details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
    /// drawing a box inside a box. It is optional — a section holding a single
    /// field is already named by its heading.
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
        .padding(.vertical, 4)
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

    /// Saves in place rather than popping back. The toast is the receipt, and a
    /// screen that leaves the moment you tap Save takes its own confirmation
    /// with it — on the one screen where a silent failure means the next quote
    /// goes out with no business name on it.
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
