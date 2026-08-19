//
//  DictationLanguage.swift
//  Verbal
//
//  Which language the app listens in.
//
//  It used to be inferred from the phone and never mentioned again, which is
//  wrong for the people this app is for: a tradesperson whose phone is in one
//  language but who quotes jobs in another, or whose region fallback hands a
//  British accent to the American model. Neither shows up as an error — the
//  words just come back subtly wrong, quote after quote.
//
//  So the choice is stored, and both the recorder and Settings read it here.
//

import Foundation
import Speech

enum DictationLanguage {
    /// A locale identifier; absent or empty means automatic.
    static let defaultsKey = "dictationLocale"

    /// The user's explicit choice, if they made one. Read straight from
    /// `UserDefaults` rather than `@AppStorage` because the recorder is not a
    /// view and needs the same answer Settings shows.
    static var storedIdentifier: String? {
        let stored = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return stored.isEmpty ? nil : stored
    }

    static var isOverridden: Bool { storedIdentifier != nil }

    /// The locale to transcribe in: what the user picked, or our own guess.
    ///
    /// A stored choice is passed through `supportedLocale(equivalentTo:)` so a
    /// language saved on another device — or one Apple has since dropped —
    /// resolves to the nearest model that does exist here instead of failing.
    /// If even that comes up empty we fall back to the guess, because a
    /// recording in the wrong language still beats a mic that refuses to start.
    static func resolved() async -> Locale? {
        if let identifier = storedIdentifier {
            let locale = Locale(identifier: identifier)
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
                return supported
            }
        }
        return await automatic()
    }

    /// The locale to transcribe in when nobody has said — one the model
    /// actually exists in.
    ///
    /// `Locale.current` used to go straight to `SpeechTranscriber`, which is the
    /// phone's setting rather than a promise that Apple built a model for it. A
    /// tradesperson whose phone is set to a language with no speech model got a
    /// failed recording where the words were fine; the model for them was never
    /// on the device.
    ///
    /// Region matters too, and quietly: en_US and en_GB are different models,
    /// and asking the American one to hear a British accent is a mis-hearing per
    /// sentence rather than an outright failure — the worse of the two, because
    /// nothing on screen says it happened.
    ///
    /// So: the exact locale, then the same language spoken elsewhere, then
    /// English, which is what the app itself is written in and the language its
    /// prompts read. Nil only when even that is missing, which is a state the
    /// caller has to tell the user about rather than push a microphone at.
    static func automatic() async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        let device = Locale.current

        func best(_ code: Locale.LanguageCode) -> Locale? {
            let candidates = supported.filter { $0.language.languageCode == code }
            guard !candidates.isEmpty else { return nil }
            // The phone's own region reads its owner's accent best.
            if let exact = candidates.first(where: { $0.region == device.region }) {
                return exact
            }
            // Falling back across regions is already a compromise; en_US is the
            // most widely trained of them and a stable choice, rather than
            // whichever locale Apple happened to list first.
            if let widest = candidates.first(where: { $0.region == Locale.Region("US") }) {
                return widest
            }
            return candidates.first
        }

        guard let language = device.language.languageCode else { return best(.english) }
        return best(language) ?? best(.english)
    }

    /// Every language with a model, in the order a person would look for one.
    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales
            .sorted { label(for: $0).localizedCompare(label(for: $1)) == .orderedAscending }
    }

    /// The ones already downloaded, so the picker can say which are ready to
    /// use without a wait.
    static func installedLocales() async -> Set<String> {
        Set(await SpeechTranscriber.installedLocales.map(\.identifier))
    }

    /// The language's name in the user's own language, e.g. "English (United
    /// Kingdom)".
    static func label(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }

    /// What the Settings row and the record screen say. Automatic names what it
    /// resolved to, because "Automatic" on its own tells a user with a
    /// mis-heard transcript nothing at all.
    static func summaryLabel() async -> String {
        // Nothing resolved means iOS has no model to offer here at all — say so
        // plainly, because "Automatic" over a mic that can't start is a lie.
        guard let locale = await resolved() else { return "None available" }
        return isOverridden ? label(for: locale) : "Automatic (\(label(for: locale)))"
    }
}
