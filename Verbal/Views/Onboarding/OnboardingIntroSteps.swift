//
//  OnboardingIntroSteps.swift
//  Verbal
//
//  The first act: the problem, their own numbers, and the setup questions.
//
//  The ordering is the point. The five setup questions were always here, and
//  answered cold they are a form. Asked after someone has named the way they
//  write quotes today and seen what it costs them in a year, they are the
//  first thing being done about it.
//

import SwiftUI

// MARK: - 1 · The hook

/// The first thing anyone sees: the real app, in a phone, under the problem it
/// exists to solve.
///
/// The phone was here before and carried the promise on its own, which said
/// what the app does but never why anyone would want it. The line above it is
/// the missing half — the screen now answers something rather than announcing
/// something.
///
/// The frame is here and the film isn't. Until it is, the glass holds a quote
/// rather than a play button: a still of the thing itself says more than an
/// icon promising one, and it is the real `LineItemsCard`, so it can't quietly
/// stop resembling the app. To drop the clip in, replace `OnboardingPhoneScreen`
/// inside `DevicePreview` with a muted, controls-free looping player. Keep it
/// short and silent — this plays before anyone has agreed to anything.
struct OnboardingHookStep: View {
    let currencyCode: String

    var body: some View {
        VStack(spacing: 14) {
            Text("Quotes shouldn't cost\nyou your evenings.")
                .font(.robotoSlab(28, relativeTo: .title))
                .foregroundStyle(Color(.mainText))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            DevicePreview {
                OnboardingPhoneScreen(currencyCode: currencyCode)
            }
            // Held to a share of the width rather than filling it. At full
            // width the phone crowded its own caption and reached for the
            // button, which made a screen with three things on it feel full.
            .frame(width: 246)
            .frame(maxWidth: .infinity)

            // These two flexible gaps deliberately match: the promise belongs
            // halfway between the phone showing the result and the button that
            // lets someone try it, rather than visually attached to either.
            Spacer(minLength: 16)

            VStack(alignment: .center, spacing: 10) {
                promiseLine("Speak it.", icon: "OnboardingSpeak")
                promiseLine("Send it.", icon: "OnboardingSend")
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func promiseLine(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
        }
        .font(.robotoSlab(32, relativeTo: .title))
        .foregroundStyle(Color(.mainText))
    }
}

// MARK: - 2 · How they do it today

/// Naming the problem in their own words, before the app claims to solve it.
///
/// Nothing in the app behaves differently for any of these answers. It is here
/// because the conclusion needs something to hand back: an app telling you it
/// saves your evenings is marketing, and the same sentence three minutes after
/// you said "on my phone, at night" is a reply.
struct OnboardingMethodStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeading(
                title: "How do you write\nquotes now?",
                subtitle: "So the rest of this knows what it's replacing."
            )
            VStack(spacing: 10) {
                ForEach(OnboardingAnswers.Method.allCases) { method in
                    OnboardingOptionRow(text: method.label,
                                        isPicked: model.answers.method == method,
                                        icon: Self.icon(for: method)) {
                        model.answers.method = model.answers.method == method ? nil : method
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: model.answers.method)
        }
    }

    /// The mapping lives here rather than on `Method` so the answers stay a
    /// plain value type with no opinion about how they're drawn.
    ///
    /// The spreadsheet reuses the document mark from the quote detail page: it
    /// is the same object in both places — a written-out quote — and drawing a
    /// second one would be two marks for one idea.
    private static func icon(for method: OnboardingAnswers.Method) -> ImageResource? {
        switch method {
        case .paper: return .methodPaper
        case .phoneAtNight: return .methodPhone
        case .spreadsheet: return .quoteDocument
        case .losingThem: return .methodLosingJob
        }
    }
}

// MARK: - 3 · Quote volume

/// The first half of the time estimate. It gets its own screen because this is
/// a quick decision, not a compact form: one question and four easy taps.
struct OnboardingQuoteVolumeStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeading(
                title: "How many quotes\ndo you write a week?",
                subtitle: "A rough guess is enough."
            )

            VStack(spacing: 10) {
                ForEach(OnboardingAnswers.volumeOptions, id: \.value) { option in
                    OnboardingOptionRow(text: option.label,
                                        isPicked: model.answers.quotesPerWeek == option.value) {
                        model.answers.quotesPerWeek = option.value
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.answers.quotesPerWeek)
    }
}

// MARK: - 4 · Quote duration

/// The second half of the estimate. It follows the volume screen rather than
/// sharing it, giving the answer the same clear, tap-first treatment.
struct OnboardingQuoteDurationStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeading(
                title: "How long does one\nquote usually take?",
                subtitle: "From starting it to sending it."
            )

            VStack(spacing: 10) {
                ForEach(OnboardingAnswers.durationOptions, id: \.value) { option in
                    OnboardingOptionRow(text: option.label,
                                        isPicked: model.answers.minutesPerQuote == option.value) {
                        model.answers.minutesPerQuote = option.value
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.answers.minutesPerQuote)
    }
}

// MARK: - 5 · The 'aha'

/// Their week, multiplied out.
///
/// The only screen in the introduction that tells them something instead of
/// asking. Every number on it came off the screen before, which is what stops
/// it reading as a claim — the app isn't asserting that quoting is expensive,
/// it is doing the arithmetic they never sat down to do.
///
/// Skipping the two questions leaves nothing to multiply, and the screen says
/// the general version rather than inventing an average and attributing it to
/// them.
struct OnboardingStatStep: View {
    let answers: OnboardingAnswers

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let perMonth = answers.hoursPerMonth, answers.hoursSavedPerYear != nil {
                // This is a conclusion, not another form. Centre the three
                // parts as one thought so the user's own number owns the page.
                VStack(spacing: 0) {
                    Text("That's \(OnboardingAnswers.spoken(hours: perMonth))\na month.")
                        .font(.robotoSlab(32, relativeTo: .largeTitle))
                        .foregroundStyle(Color(.mainText))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 24)

                    VStack(spacing: 22) {
                        VStack(spacing: 6) {
                            Text("\(Int((answers.hoursPerYear ?? 0).rounded())) hours")
                                .font(.robotoSlab(48, relativeTo: .largeTitle))
                                .foregroundStyle(OnboardingStyle.action)
                            Text("a year back for the work that matters.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        Text("Spend that time on the job — not chasing paperwork. Verbal keeps the details of each job clear while they're still fresh.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                OnboardingHeading(
                    title: "The job is done.\nThe quote still waits.",
                    subtitle: "Verbal turns the work you have just finished into a quote before you leave."
                )

                // This is the honest fallback when the time questions were
                // skipped: show the change in workflow without pretending we
                // know how long their own quoting takes.
                VStack(alignment: .leading, spacing: 0) {
                    workflowStep(icon: "checkmark", title: "Finish the job",
                                 detail: "The work is still fresh.")
                    workflowConnector
                    workflowStep(icon: "mic.fill", title: "Say what you did",
                                 detail: "Verbal writes the quote as you speak.")
                    workflowConnector
                    workflowStep(icon: "paperplane.fill", title: "Send it before you leave",
                                 detail: "A clear quote, ready for the customer.")
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
    }

    private func workflowStep(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OnboardingStyle.action)
                .frame(width: 34, height: 34)
                .background(OnboardingStyle.action.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private var workflowConnector: some View {
        Rectangle()
            .fill(OnboardingStyle.action.opacity(0.25))
            .frame(width: 1, height: 24)
            .padding(.leading, 16.5)
            .padding(.vertical, 5)
    }
}

// MARK: - 5 · Trade

/// The trade is the one answer with no sensible default, and it reaches the
/// extraction on every quote — "20 mil" means one thing to a plumber and
/// another to an electrician. So it is the one question that is asked rather
/// than offered.
struct OnboardingTradeStep: View {
    @Bindable var model: OnboardingModel
    var focused: FocusState<OnboardingField?>.Binding

    private static let otherTrade = "Something else"

    private static let trades = [
        "Electrician", "Plumber", "Carpenter", "Tiler",
        "Painter", "Plasterer", "Builder", "Roofer",
        "Landscaper", otherTrade
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeading(
                title: "What's your trade?",
                subtitle: "So a quote knows that “20 mil” means your 20 mil."
            )

            // A grid of taps rather than a text field: this is answered once,
            // standing in a van, and a keyboard is the slowest way to say a
            // word the app could have offered.
            FlowLayout(spacing: 8) {
                ForEach(Self.trades, id: \.self) { trade in
                    let isOther = trade == Self.otherTrade
                    let picked = isOther ? model.isCustomTrade
                                         : (!model.isCustomTrade && model.trade == trade)
                    OnboardingChip(text: trade, isPicked: picked) {
                        if isOther {
                            // The stored trade is whatever they type, not the
                            // words "Something else" — that string was being
                            // sent to the extraction as trade context, where it
                            // says less than nothing.
                            model.isCustomTrade = true
                            model.trade = ""
                        } else {
                            model.isCustomTrade = false
                            model.trade = trade
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: model.trade)
            .animation(.easeInOut(duration: 0.15), value: model.isCustomTrade)

            // Typed rather than tapped, because there is no list of every trade
            // there is. Whatever goes here reaches the extraction as context.
            if model.isCustomTrade {
                OnboardingFieldBox {
                    TextField("Locksmith, glazier, welder…", text: $model.trade)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused(focused, equals: .customTrade)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - 6 · The jobs they do

/// Ticking, not typing. The point of this screen is that it can be answered
/// while holding something in the other hand.
///
/// The heading takes their trade, and the line under the grid counts what they
/// have ticked. Both are the same move: an answer given two screens ago is
/// visibly being used, which is the difference between filling in a form and
/// setting something up.
struct OnboardingJobsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingHeading(
                title: "Which of these\ndo you do?",
                subtitle: "Standard work \(OnboardingCopy.article(for: model.trade)). Tick what you actually take on — Verbal prices these for you when you quote them."
            )

            FlowLayout(spacing: 8) {
                ForEach(TradePresets.jobs(for: model.trade)) { job in
                    OnboardingChip(text: job.name,
                                   isPicked: model.pickedJobs.contains(job.name)) {
                        if model.pickedJobs.contains(job.name) {
                            model.pickedJobs.remove(job.name)
                        } else {
                            model.pickedJobs.insert(job.name)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: model.pickedJobs)

            if !model.pickedJobs.isEmpty {
                Text("\(model.pickedJobs.count) ticked — that's most of a rate card already.")
                    .font(.footnote)
                    .foregroundStyle(OnboardingStyle.action)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - 7 · What they charge

/// The screen the rest of the flow is paid for by.
///
/// These numbers price the quote they are about to record, fill the rate card
/// they arrive with, and give the conclusion something to measure a
/// subscription against. It is also the longest screen in the flow and the only
/// one with no natural end, so it counts out loud how far through it is.
///
/// Currency lives here rather than on a screen of its own: it is the same
/// question as "what do you charge", asked in the same breath, and it is
/// already answered from the device's region for most people.
struct OnboardingPricesStep: View {
    @Bindable var model: OnboardingModel
    @Binding var currencyCode: String
    var focused: FocusState<OnboardingField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeading(
                title: "Roughly what\ndo you charge?",
                subtitle: "A rough number beats none — you can correct any of them later."
            )

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(AppCurrency.allCases) { option in
                        OnboardingChip(text: "\(option.symbol) \(option.rawValue)",
                                       isPicked: currencyCode == option.rawValue) {
                            currencyCode = option.rawValue
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            // Runs to the edges of the screen rather than stopping at the
            // page's margin, the same as the quote screen's chips. Clipped to
            // the margin the row reads as a short list that happens to be cut
            // off; running out past it, it reads as one that carries on.
            .scrollClipDisabled()

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.pickedList) { job in
                        priceRow(name: job.name, unit: job.unit, field: .price(job.name),
                                 text: Binding(
                                    get: { model.prices[job.name] ?? "" },
                                    set: { model.prices[job.name] = $0 }
                                 ))
                    }

                    // Asked of everyone, including the trades whose preset list
                    // already offers an hourly rate, because this is the number
                    // the conclusion measures the subscription against. Kept
                    // visually apart from the ticked jobs: it is the one row
                    // here they didn't ask for.
                    if !model.pickedList.contains(where: { $0.name == OnboardingModel.hourlyRateName }) {
                        priceRow(name: "Your hourly rate",
                                 unit: "hour",
                                 field: .hourlyRate,
                                 text: $model.hourlyRateText)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func priceRow(name: String, unit: String,
                          field: OnboardingField, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Color(.mainText))
                    .lineLimit(1)
                Text("per \(unit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                Text(AppCurrency.current.symbol)
                    .foregroundStyle(.secondary)
                TextField("0", text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused(focused, equals: field)
                    .frame(width: 72)
            }
            .font(.callout.monospacedDigit())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.cardSurface),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }
}

// MARK: - 8 · The business

/// The same three fields as before, asked as the customer's view of them.
///
/// "Business details" is admin, and admin is what someone skips. What actually
/// goes in these boxes is the top of the document a customer opens — and this
/// name is on the summary screen two taps later, so the answer is visibly used
/// before anyone is asked for another one.
struct OnboardingBusinessStep: View {
    @Bindable var model: OnboardingModel
    var focused: FocusState<OnboardingField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingHeading(
                title: "What goes at the\ntop of the quote?",
                subtitle: "This is the name your customer reads before they read the price."
            )

            OnboardingFieldBox {
                TextField("Your business name", text: $model.businessName)
                    .textInputAutocapitalization(.words)
                    .focused(focused, equals: .businessName)
            }

            Toggle(isOn: $model.isTaxRegistered.animation(.easeInOut(duration: 0.2))) {
                Text("I'm tax registered")
                    .font(.callout)
                    .foregroundStyle(Color(.mainText))
            }
            .tint(OnboardingStyle.action)

            if model.isTaxRegistered {
                OnboardingFieldBox {
                    HStack(spacing: 8) {
                        Text("Rate")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TextField("20", text: $model.taxRate)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.callout.monospacedDigit())
                            .focused(focused, equals: .taxRate)
                            .frame(width: 60)
                        Text("%").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 9 · Read back

/// Their own answers, listed, with nothing added.
///
/// The last screen of the introduction and the cheapest one in it: no question,
/// no claim, just the five things they said. It exists because the next act
/// asks them to speak into a microphone, and someone who has just watched the
/// app repeat their own setup back correctly is far likelier to.
struct OnboardingSummaryStep: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            OnboardingHeading(
                title: "Your setup is\nready to quote.",
                subtitle: "We’ll use these details on every quote. You can change them whenever you need."
            )

            // Lead with the business the customer will see, then keep the
            // practical setup details quiet underneath. This reads as a
            // finished identity rather than a miniature Settings screen.
            HStack(alignment: .center, spacing: 14) {
                Image(.recordingIntroReview)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(OnboardingStyle.action)

                VStack(alignment: .leading, spacing: 3) {
                    Text(identityTitle)
                        .font(.robotoSlab(25, relativeTo: .title2))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Text(identitySubtitle)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(OnboardingStyle.action)
                }
            }
            .padding(.vertical, 4)

            if !model.draftRates.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your rate card")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    ForEach(Array(model.draftRates.prefix(3).enumerated()), id: \.offset) { _, rate in
                        rateCardRow(rate)
                    }

                    if model.draftRates.count > 3 {
                        Text("+ \(model.draftRates.count - 3) more saved rate\(model.draftRates.count == 4 ? "" : "s")")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(OnboardingStyle.action)
                    }
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(detailFacts.enumerated()), id: \.offset) { index, fact in
                    if index > 0 {
                        Divider().padding(.vertical, 14)
                    }
                    detailRow(fact)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var identityTitle: String {
        model.summaryFacts.first(where: { $0.label == "Business" })?.value
            ?? model.summaryFacts.first(where: { $0.label == "Trade" })?.value
            ?? "Ready for your first quote"
    }

    private var identitySubtitle: String {
        guard let trade = model.summaryFacts.first(where: { $0.label == "Trade" })?.value,
              trade != identityTitle else { return "Your quote details" }
        return trade
    }

    private var detailFacts: [(label: String, value: String)] {
        model.summaryFacts.filter {
            $0.label != "Business" && $0.label != "Trade" && $0.label != "Rate card"
        }
    }

    private func detailRow(_ fact: (label: String, value: String)) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(fact.label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(fact.value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color(.mainText))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mirrors a saved item on the app's Rate card: a separate, lightly raised
    /// card with the tag plate, name, unit and value in the same hierarchy.
    private func rateCardRow(_ rate: OnboardingDraft.Rate) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.surface))
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .overlay(
                    Image(systemName: "tag.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color(.mainText))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(rate.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(AppCurrency.format(rate.price))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color(.mainText))
                        .lineLimit(1)
                }
                Text("per \(rate.unit)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color(.cardSurface), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)
    }
}

// MARK: - Shared copy

enum OnboardingCopy {
    /// "for a tiler", "for an electrician", and nothing at all when the trade
    /// was skipped — a sentence ending "Standard work for a ." is worse than
    /// the shorter one.
    static func article(for trade: String) -> String {
        let name = trade.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !name.isEmpty else { return "in your trade" }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        let article = vowels.contains(name.first ?? "x") ? "an" : "a"
        return "for \(article) \(name)"
    }
}
