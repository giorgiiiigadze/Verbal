//
//  OnboardingModel.swift
//  Verbal
//
//  Every answer the flow collects, and the list of screens that collect them.
//
//  It lives outside the view because the flow is now long enough that the
//  screens are separate files, and passing eleven bindings into each of them
//  was worse than one object. The view still owns the step index: which screen
//  is showing is a fact about the view, not about the user.
//

import Foundation
import Observation

@MainActor
@Observable
final class OnboardingModel {
    enum FeatureFlag {
        static let shortFlowKey = "shortPreAuthOnboarding"

        /// New installs use the five-step flow. Setting the key to `false`
        /// keeps the previous funnel available for the conversion experiment.
        static var usesShortFlow: Bool {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: shortFlowKey) != nil else { return true }
            return defaults.bool(forKey: shortFlowKey)
        }
    }

    /// The three acts, in the order they run. Named for what the screen does to
    /// the person reading it rather than for the field it fills, because half
    /// of them fill no field at all.
    enum Step: Hashable {
        // Introduction — the problem, their own numbers, and the setup.
        case hook, profile, method, quoteVolume, quoteDuration, stat
        case setup, trade, jobs, prices, business, summary
        // The preview of the setup they have just completed.
        case result, milestone
        // Conclusion — what they came for, what it costs, what happens next.
        case goal, commitment, expectations, notifications
    }

    // MARK: - The setup answers (these become the profile)

    var pickedJobs: Set<String> = []
    var prices: [String: String] = [:]
    var isCustomTrade = false
    var businessName = ""
    var taxRate = ""
    var isTaxRegistered = false
    /// Held as text like every other price here, so a half-typed number doesn't
    /// fight the field. Parsed once, on the way out.
    var hourlyRateText = ""

    // MARK: - The questions asked for their own sake

    var answers = OnboardingAnswers()

    private let usesShortFlow: Bool

    init(usesShortFlow override: Bool? = nil) {
        let usesShortFlow = override ?? FeatureFlag.usesShortFlow
        self.usesShortFlow = usesShortFlow
        guard usesShortFlow else { return }

        // The compact profile is an estimate, not a form. Start it with a
        // representative answer in every row so Continue is always useful and
        // the stat/paywall never lose the numbers they quote.
        answers.method = .phoneAtNight
        answers.quotesPerWeek = 4
        answers.minutesPerQuote = 20
    }

    /// The value is observable for the onboarding UI, then mirrored to the
    /// existing storage key for extraction after onboarding. Reading
    /// `UserDefaults` directly from a computed property meant a selected chip
    /// could redraw while the Continue button kept its previous disabled state.
    private var selectedTrade = UserDefaults.standard.string(forKey: "pendingTrade") ?? ""

    var trade: String {
        get { selectedTrade }
        set {
            selectedTrade = newValue
            UserDefaults.standard.set(newValue, forKey: "pendingTrade")
        }
    }

    // MARK: - The flow

    /// The steps this particular user will see.
    ///
    /// A trade with no preset jobs skips the list that would fit nobody, and
    /// nothing ticked means there is nothing to price.
    var steps: [Step] {
        if usesShortFlow {
            return [.hook, .profile, .stat, .setup, .notifications]
        }

        var list: [Step] = [.hook, .method, .quoteVolume, .quoteDuration, .stat, .trade]
        // Pricing a whole list of jobs before the first quote is admin work,
        // not setup. Collect one useful anchor now; the Rate Card can grow
        // once the user has seen a real quote.
        list.append(.prices)
        // The outcome is already shown in the "Your time back" step. Do not
        // repeat it with an empty rate-card tally before the user reaches the app.
        list.append(contentsOf: [.business, .summary, .milestone,
                                 .goal, .commitment, .expectations, .notifications])
        return list
    }

    // MARK: - What they told us, as things worth showing

    var pickedList: [TradePresets.Job] {
        TradePresets.jobs(for: trade).filter { pickedJobs.contains($0.name) }
    }

    /// What they typed, as rates worth saving. A blank or unparseable price is
    /// left out rather than saved as a rate with no price — the rate card
    /// exists to avoid exactly that.
    var draftRates: [OnboardingDraft.Rate] {
        var rates = pickedList.compactMap { job -> OnboardingDraft.Rate? in
            guard let value = Self.number(from: prices[job.name]) else { return nil }
            return OnboardingDraft.Rate(name: job.name, unit: job.unit,
                                        price: value, type: TradePresets.type)
        }
        // The hourly rate is a rate like any other, and the presets already
        // carry an "Hourly rate" for trades with no list of their own. Saving
        // it as one means the number that anchors the price of a subscription
        // is also a line the extraction can price, rather than a figure
        // collected only to argue with.
        if let hourly = Self.number(from: hourlyRateText),
           !rates.contains(where: { $0.name == Self.hourlyRateName }) {
            rates.append(OnboardingDraft.Rate(name: Self.hourlyRateName, unit: "hour",
                                              price: hourly, type: TradePresets.type))
        }
        return rates
    }

    static let hourlyRateName = "Hourly rate"

    /// How many of the ticked jobs have a price against them, for the counter
    /// on the pricing screen. The screen is the longest in the flow and the
    /// only one with no natural end, so it says where it is up to.
    var pricedCount: Int {
        pickedList.filter { Self.number(from: prices[$0.name]) != nil }.count
    }

    var hasAnyRate: Bool { !draftRates.isEmpty }

    /// A short description of their setup, for the screen that reads it back.
    /// Only the parts they actually answered — a summary listing blanks is a
    /// list of things they failed to do.
    var summaryFacts: [(label: String, value: String)] {
        var facts: [(String, String)] = []
        let name = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { facts.append(("Business", name)) }
        if !trade.isEmpty { facts.append(("Trade", trade)) }
        if !draftRates.isEmpty {
            facts.append(("Rate card", "\(draftRates.count) \(draftRates.count == 1 ? "rate" : "rates")"))
        }
        facts.append(("Currency", "\(AppCurrency.current.displayName) (\(AppCurrency.current.symbol))"))
        if isTaxRegistered, let rate = Self.number(from: taxRate) {
            facts.append(("Tax", "\(rate.formatted(.number.precision(.fractionLength(0...2))))%"))
        }
        return facts
    }

    // MARK: - Saving

    /// Everything but the trade, which already has its own key and its own
    /// adoption. Saved on the way out rather than as it's typed: half an answer
    /// isn't worth carrying into an account.
    func saveDraft() {
        var draft = OnboardingDraft()
        let name = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.businessName = name.isEmpty ? nil : name
        if isTaxRegistered {
            draft.taxRate = Self.number(from: taxRate).map { max(0, $0) }
        }
        draft.rates = draftRates
        if draft.isEmpty { OnboardingDraft.clear() } else { draft.save() }

        // Saved separately and not cleared with the draft: the paywall reads
        // these the first time it appears, which is after sign-in has emptied
        // the draft into the profile.
        answers.hourlyRate = Self.number(from: hourlyRateText)
        answers.save()
    }

    /// Commas for decimal points are the norm in most of the currencies this
    /// app offers, and a rate typed as "37,50" was silently becoming no rate
    /// at all.
    static func number(from text: String?) -> Double? {
        guard let text else { return nil }
        let cleaned = text.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }
}
