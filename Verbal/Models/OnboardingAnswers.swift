//
//  OnboardingAnswers.swift
//  Verbal
//
//  The answers onboarding asks for its own sake rather than the app's.
//
//  The setup questions — trade, jobs, prices, business — all end up somewhere
//  the app reads later, and `OnboardingDraft` carries those across sign-in.
//  These don't. They exist to tell someone something about their own week, and
//  then to be quoted back at them on the screen that asks for money.
//
//  Kept apart from the draft for exactly that reason: the draft is written into
//  the profile on first sign-in and then cleared, whereas the paywall wants
//  this line the first time it appears — which is after that clear has run.
//

import Foundation

struct OnboardingAnswers: Codable, Sendable {
    /// How they write quotes today. The point of asking is the problem, not the
    /// answer: nothing in the app behaves differently because of it. It comes
    /// back on the goal screen as the thing they said they wanted to stop.
    enum Method: String, Codable, CaseIterable, Identifiable {
        case paper
        case phoneAtNight
        case spreadsheet
        case losingThem

        var id: String { rawValue }

        var label: String {
            switch self {
            case .paper: return "Pen and paper"
            case .phoneAtNight: return "On my phone, at night"
            case .spreadsheet: return "A spreadsheet or a template"
            case .losingThem: return "I put it off, and lose the job"
            }
        }

        /// Said back to them in the conclusion, as a goal rather than a habit.
        /// Phrased as the end of something, because that is what they picked it
        /// for — nobody taps "on my phone, at night" approvingly.
        var goal: String {
            switch self {
            case .paper: return "No more writing them out by hand."
            case .phoneAtNight: return "No more quotes at nine at night."
            case .spreadsheet: return "No more fighting with a template."
            case .losingThem: return "No more jobs lost to a slow quote."
            }
        }
    }

    /// Buckets rather than a typed number: this is arithmetic for a sentence,
    /// not bookkeeping, and a chip is answerable in a van.
    static let volumeOptions: [(label: String, value: Int)] = [
        ("1–2 quotes", 2), ("3–5 quotes", 4), ("6–10 quotes", 8),
        ("More than 10 quotes", 14)
    ]

    static let durationOptions: [(label: String, value: Int)] = [
        ("About 10 minutes", 10), ("About 20 minutes", 20),
        ("About 30 minutes", 30), ("An hour or more", 60)
    ]

    /// What the app claims it takes instead. Deliberately generous to the
    /// old way — a minute, not the forty seconds it usually is — because the
    /// number on the screen is a promise the next screen has to keep.
    static let verbalMinutesPerQuote = 1.0

    /// Weeks in a month, near enough. `4` would quietly under-count by most of
    /// a week a year, and this number is shown to the user as a fact.
    private static let weeksPerMonth = 4.33

    var method: Method?
    var quotesPerWeek: Int?
    var minutesPerQuote: Int?
    /// 1...5, from the commitment check. Nothing reads it but the screen after
    /// it; it is stored because a number someone chose about themselves is
    /// worth being able to repeat back.
    var commitment: Int?
    /// Their own charge-out rate, which is what the price of a subscription is
    /// measured against in the conclusion. Nil when they skipped the question,
    /// and the anchor silently becomes a plainer sentence.
    var hourlyRate: Double?

    // MARK: - The arithmetic behind the 'aha'

    /// Hours a month spent writing quotes, on their own two numbers. Nil until
    /// both have been answered — half of this sum is not a smaller version of
    /// it, it is a made-up one.
    var hoursPerMonth: Double? {
        guard let quotesPerWeek, let minutesPerQuote else { return nil }
        return Double(quotesPerWeek) * Double(minutesPerQuote) * Self.weeksPerMonth / 60
    }

    var hoursPerYear: Double? {
        hoursPerMonth.map { $0 * 12 }
    }

    /// The hours that would come back, not the hours spent — the app still
    /// costs a minute a quote, and a saving that ignores its own cost is the
    /// kind of number that makes the rest of the screen untrustworthy.
    var hoursSavedPerYear: Double? {
        guard let quotesPerWeek, let minutesPerQuote else { return nil }
        let saved = max(0, Double(minutesPerQuote) - Self.verbalMinutesPerQuote)
        return Double(quotesPerWeek) * saved * Self.weeksPerMonth * 12 / 60
    }

    /// How long they'd have to work to earn back a month of Verbal, in whole
    /// minutes of their own time. The one comparison on the expectations screen
    /// that is in their units rather than a coffee shop's.
    func minutesOfLabour(matching price: Double) -> Int? {
        guard let hourlyRate, hourlyRate > 0 else { return nil }
        return max(1, Int((price / hourlyRate * 60).rounded()))
    }

    /// Rounded the way a person says it out loud. 6.4 hours is "about 6", and
    /// a screen that says "6.4 hours a month" is doing sums at someone rather
    /// than telling them something.
    static func spoken(hours: Double) -> String {
        hours < 1.5 ? "about an hour" : "about \(Int(hours.rounded())) hours"
    }

    // MARK: - Storage

    private static let key = "onboardingAnswers"

    static func load() -> OnboardingAnswers {
        guard let data = UserDefaults.standard.data(forKey: key),
              let answers = try? JSONDecoder().decode(OnboardingAnswers.self, from: data)
        else { return OnboardingAnswers() }
        return answers
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
