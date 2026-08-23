//
//  AccountView.swift
//  Verbal
//
//  The Account tab: who is signed in, and everything set once and left alone —
//  the business details printed on quotes, quote defaults, currency, the
//  language the mic listens in, and the doors out.
//
//  These were two screens until now: a profile form in the tab, and settings
//  behind a gear in its corner. That put the things people come looking for —
//  currency, sign out, help — one tap behind a screen named after something
//  else, while the form they fill in once at setup held the top level. The gear
//  is gone with the split, and so is the toolbar dance where Save had to take
//  its place to avoid two trailing buttons.
//
//  A `List` with real sections, unlike the screens it leads to. Every row here
//  is a stock control — a link, a picker, a destructive button — and drawing
//  those by hand costs the press states, the swipe-back highlight and the
//  Dynamic Type behaviour that come free, to gain nothing the eye can name. The
//  card colour and the page ground are the app's own, so it still sits in the
//  same room as Home.
//

import SwiftUI

struct AccountView: View {
    @Environment(SessionStore.self) private var session

    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue
    @AppStorage(ScheduledVisitNotifications.enabledKey) private var remindersEnabled = true
    @AppStorage(ScheduledVisitNotifications.leadTimeKey) private var reminderLeadTime = ScheduledVisitReminderLeadTime.atTime.rawValue
    @AppStorage(RecordingPreferences.hapticsEnabledKey) private var recordingHapticsEnabled = true
    @AppStorage(AppAppearance.defaultsKey) private var appearance = AppAppearance.system.rawValue
    /// Read only to refresh the row's value when the picker writes it.
    @AppStorage(DictationLanguage.defaultsKey) private var dictationLocale = ""

    /// What the dictation row reads on the right — resolved, so automatic still
    /// names the language it picked.
    @State private var dictationLabel = ""

    @State private var showSignOutConfirmation = false
    @State private var toast: Toast?
    /// The currency the user picked, held until they say what should happen to
    /// their saved rates.
    @State private var pendingCurrency: CurrencyTarget?

    /// Identifiable wrapper so a picked code can drive `.sheet(item:)`.
    private struct CurrencyTarget: Identifiable { let id: String }

    /// Saved rates that a currency switch would reinterpret.
    private var pricedRates: [RateCardItem] {
        session.rateCard.filter { $0.unitPrice != nil }
    }

    private var currency: Binding<AppCurrency> {
        Binding(
            get: { AppCurrency(rawValue: currencyCode) ?? .usd },
            set: { picked in
                guard picked.rawValue != currencyCode else { return }
                // A rate card stores bare numbers, so this setting is the only
                // thing saying whether 50 means $50 or £50. Switching it with
                // rates saved would redenominate all of them in silence, so ask
                // first. With nothing priced there is nothing to reinterpret.
                if pricedRates.isEmpty {
                    currencyCode = picked.rawValue
                    toast = Toast(style: .success, message: "Main currency set to \(picked.rawValue)")
                } else {
                    pendingCurrency = CurrencyTarget(id: picked.rawValue)
                }
            }
        )
    }

    private var notificationSummary: String {
        guard remindersEnabled else { return "Off" }
        return ScheduledVisitReminderLeadTime(rawValue: reminderLeadTime)?.label ?? ScheduledVisitReminderLeadTime.atTime.label
    }

    private var appearanceLabel: String {
        (AppAppearance(rawValue: appearance) ?? .system).label
    }

    /// The page's heading. Their name where the account has one, and otherwise
    /// the business — never a blank line where a title should be.
    private var displayName: String {
        if let name = session.profile?.fullName?.trimmedOrNil { return name }
        if let name = session.businessProfile?.businessName?.trimmedOrNil { return name }
        return "Your account"
    }

    var body: some View {
        List {
            // The face, the name and the address they signed in with — and a
            // tap on all of it to reach the details a client actually sees.
            // The same row Settings screens elsewhere open with, because it is
            // the same question: who is this, and where do I go to change it.
            Section {
                NavigationLink {
                    BusinessDetailsView()
                } label: {
                    header
                }
                NavigationLink {
                    OtherView()
                } label: {
                    Label("Other", systemImage: "ellipsis.circle")
                }
            } footer: {
                Text("Your business name, number and address as a client sees them, and the trade Verbal reads your jobs against.")
            }
            .listRowBackground(Color(.cardSurface))

            // Currency belongs here rather than in a section of its own: it is
            // a quote-formatting setting, and one row wrapped in its own header
            // and footer is more chrome than content on a screen this short.
            Section {
                NavigationLink {
                    QuoteDefaultsView()
                } label: {
                    Label("Quote defaults", systemImage: "doc.plaintext")
                }
                Picker("Main currency", selection: currency) {
                    ForEach(AppCurrency.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
            } header: {
                Text("Quotes")
            } footer: {
                Text("Your letterhead, validity, tax and standard terms, applied to every new quote. The currency also formats your rate card.")
            }
            .listRowBackground(Color(.cardSurface))

            // The language the mic hears, which was inferred from the phone and
            // never mentioned. It sits above the doors rather than inside
            // "Other": getting it wrong spoils every recording, which makes it
            // a setting people come looking for.
            Section {
                NavigationLink {
                    RecordingPreferencesView()
                } label: {
                    LabeledContent("Recording preferences", value: recordingHapticsEnabled ? "Haptics on" : "Haptics off")
                }
                NavigationLink {
                    DictationLanguageView()
                } label: {
                    LabeledContent("Dictation language", value: dictationLabel)
                }
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    LabeledContent("Notifications", value: notificationSummary)
                }
                NavigationLink {
                    AppearanceView()
                } label: {
                    LabeledContent("Appearance", value: appearanceLabel)
                }
            } header: {
                Text("Recording")
            }
            .listRowBackground(Color(.cardSurface))

            // Three doors rather than three more sections. Support, legal and
            // deletion were all laid out here in full, which put "Delete
            // account" one flick from the currency picker and made a screen with
            // two real settings on it look like a screen with nine.
            Section {
                NavigationLink {
                    HelpView()
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .listRowBackground(Color(.cardSurface))

            // Signing out stays in the open: it is routine, reversible, and the
            // thing people actually come here to do. Deleting the account is
            // none of those, and lives behind "Other".
            Section {
                Button("Sign out", role: .destructive) {
                    showSignOutConfirmation = true
                }
            }
            .listRowBackground(Color(.cardSurface))
        }
        // A list opens with room for a large title; this one has a face and a
        // name in that space instead, and the stock inset left it floating.
        .contentMargins(.top, 6, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color(.homeBackground))
        // The bar names the screen, as it does on every screen this one leads
        // to. The row below it is the account, not the title.
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign out of Verbal?", isPresented: $showSignOutConfirmation) {
            Button("Sign out", role: .destructive) {
                Task { try? await session.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your quotes stay safe — you'll just need to sign in again.")
        }
        .sheet(item: $pendingCurrency) { target in
            ConvertRateCardSheet(items: pricedRates,
                                 fromCode: currencyCode,
                                 toCode: target.id) { converted in
                currencyCode = target.id
                if converted {
                    Task { await session.refreshRateCard() }
                    toast = Toast(style: .success, message: "Rates converted to \(target.id)")
                } else {
                    toast = Toast(style: .success, message: "Main currency set to \(target.id)")
                }
            }
        }
        .toast($toast)
        // Keyed on the stored choice so the row updates when the user comes
        // back from the picker.
        .task(id: dictationLocale) {
            dictationLabel = await DictationLanguage.summaryLabel()
        }
    }

    // MARK: - Header

    /// Face, name, account address — the same heading a client's page opens
    /// with, sized for a row rather than a title.
    ///
    /// The name and the face come from the account they signed in with and
    /// can't be edited here; what the tap leads to is the business the client
    /// sees, which is what the footer under the row says.
    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(image: session.avatarImage,
                       urlString: session.profile?.avatarUrl, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.robotoSlab(19, relativeTo: .headline))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)
                if let email = session.email, !email.isEmpty {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
