//
//  OnboardingView.swift
//  Verbal
//
//  The screens between installing the app and signing in.
//
//  Deliberately not a carousel of promises. The first screen shows the app
//  doing its one trick, because a voice-to-quote app is easier to prove than to
//  describe; the rest ask the only questions worth asking before there is an
//  account — and every one of those answers does real work rather than being
//  collected for its own sake.
//
//  They run before auth, so there is no user to save anything to. Both answers
//  are held on the device and written to the profile on the first sign-in.
//

import SwiftUI
import UserNotifications

struct OnboardingView: View {
    /// Called when the last step is finished, to hand over to the auth screen.
    var onContinue: () -> Void

    @AppStorage("pendingTrade") private var pendingTrade = ""
    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    @State private var step = 0
    @Namespace private var glass

    /// Jobs ticked on the presets step, and the prices typed for them. Held as
    /// text so a half-typed number doesn't fight the field.
    @State private var pickedJobs: Set<String> = []
    @State private var prices: [String: String] = [:]
    /// True once "Something else" is tapped: the chip stays lit while the field
    /// below it holds the real answer.
    @State private var isCustomTrade = false
    @State private var businessName = ""
    @State private var taxRate = ""
    @State private var isTaxRegistered = false
    @FocusState private var focusedField: Field?

    private enum Step: Hashable {
        case trade, jobs, prices, business, reveal, notifications, video
    }

    private enum Field: Hashable {
        case customTrade
        case price(String)
        case businessName
        case taxRate
    }

    /// The steps this particular user will see. A trade with no preset list
    /// skips the jobs question rather than being shown a list that fits nobody,
    /// and pricing is skipped when nothing was ticked to price.
    private var steps: [Step] {
        var list: [Step] = [.video, .trade]
        if !TradePresets.jobs(for: pendingTrade).isEmpty {
            list.append(.jobs)
            if !pickedJobs.isEmpty { list.append(.prices) }
        }
        list.append(contentsOf: [.business, .reveal, .notifications])
        return list
    }

    /// Clamped, because `steps` shrinks underneath the index when someone swipes
    /// back and unticks every job.
    private var current: Step {
        let all = steps
        return all[min(step, all.count - 1)]
    }

    /// Asked of the list rather than compared against one case, so adding a
    /// screen to the end doesn't leave the finishing behaviour on the one
    /// before it. This is what ENDS onboarding — the button's looks are keyed
    /// to `isFirstStep` instead.
    private var isLastStep: Bool {
        step >= steps.count - 1
    }

    /// The opening screen, which is the clip. It carries the invitation into
    /// all this; every screen after it is a step through it.
    private var isFirstStep: Bool { step == 0 }

    private var pickedList: [TradePresets.Job] {
        TradePresets.jobs(for: pendingTrade).filter { pickedJobs.contains($0.name) }
    }

    /// What the user typed, as rates worth saving. A blank or unparseable price
    /// is left out rather than saved as a rate with no price — the rate card
    /// exists to avoid exactly that.
    private var draftRates: [OnboardingDraft.Rate] {
        pickedList.compactMap { job in
            let text = (prices[job.name] ?? "").replacingOccurrences(of: ",", with: ".")
            guard let value = Double(text.trimmingCharacters(in: .whitespaces)), value > 0
            else { return nil }
            return OnboardingDraft.Rate(name: job.name, unit: job.unit,
                                        price: value, type: TradePresets.type)
        }
    }

    private static let otherTrade = "Something else"
    /// Matches the lighter blue used by the paywall and quote-share action.
    private static let actionBlue = Color(red: 48 / 255, green: 92 / 255, blue: 222 / 255)

    private static let trades = [
        "Electrician", "Plumber", "Carpenter", "Tiler",
        "Painter", "Plasterer", "Builder", "Roofer",
        "Landscaper", otherTrade
    ]

    /// The trade is the one answer with no sensible default, and it reaches the
    /// extraction on every quote — "20 mil" means one thing to a plumber and
    /// another to an electrician. So it is the one question that is asked
    /// rather than offered. Everything else here has a default worth keeping.
    private var canContinue: Bool {
        switch current {
        case .trade:
            return !pendingTrade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .reveal:
            return true
        default:
            return true
        }
    }

    var body: some View {
        NavigationStack {
            content
                // A real navigation bar, so the back button is the system's own
                // circular one and the mark sits where a title sits. Drawn by
                // hand it was a row of shapes imitating a header.
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if step > 0 {
                            Button {
                                goBack()
                            } label: {
                                Image(systemName: "chevron.backward")
                            }
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        // The opening screen is deliberately just the product
                        // preview, its two-line promise and Continue. The app
                        // name returns with the setup questions.
                        if !isFirstStep {
                            HStack(spacing: 8) {
                                Image(.brandMark)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20)
                                    .foregroundStyle(Self.actionBlue)
                                Text("Verbal")
                                    .font(.robotoSlab(18, relativeTo: .headline))
                                    .foregroundStyle(Self.actionBlue)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // Never a wall: every question has a sensible answer
                        // already, and nobody should be stuck on the way to the
                        // thing they installed the app for. Nothing to skip on
                        // the reveal.
                        // Absent where the answer is required, so Skip never
                        // offers a way round a disabled Continue.
                        if step > 0, current != .reveal, current != .video, current != .trade, current != .notifications {
                            Button("Skip") { advance(requestingNotifications: false) }
                                .font(.subheadline)
                                .foregroundStyle(Color(.mainText))
                        }
                    }
                    // Bare text. The glass is the toolbar's, not the button's,
                    // so a button style can't refuse it — this is the opt-out.
                    // Two glass capsules either side of the mark read as a pair
                    // of equal choices, and skipping isn't one of those.
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button {
                            focusedField = nil
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                        }
                        .accessibilityLabel("Dismiss keyboard")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var content: some View {
        ZStack {
            // Plain ground. These screens ask five questions and show a sample
            // quote, and drawn waves behind a form is decoration competing with
            // the thing being read. The illustration stays on sign-in, where
            // there is nothing to answer and it is the whole of the welcome —
            // so arriving there now reads as the app opening rather than as
            // more of the same.
            Color(.homeBackground).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch current {
                    case .trade: tradeStep
                    case .jobs: jobsStep
                    case .prices: pricesStep
                    case .business: businessStep
                    case .reveal: revealStep
                    case .notifications: notificationsStep
                    case .video: videoStep
                    }
                }
                // Each step arrives from the side it was going, so the sequence
                // reads as forward motion rather than as three unrelated
                // screens sharing a background.
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 24)),
                    removal: .opacity.combined(with: .offset(x: -24))
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            // Less than the sides: the home indicator already reserves space
            // below this, and matching 24 to it left the button floating well
            // clear of the bottom of the screen.
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.3), value: step)
        // The only way back, so it is worth being generous about what counts as
        // one: a shallow drag rightwards, the same direction the steps travel,
        // rather than a precise edge swipe nobody would find.
        //
        // Vertical movement is ignored, so a thumb sliding down the chips
        // doesn't jump a step.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { drag in
                    guard step > 0 else { return }
                    let sideways = drag.translation.width
                    let vertical = abs(drag.translation.height)
                    // Through the same path as the button, so a swipe back and
                    // a tap back feel like the one action they are.
                    if sideways > 60, sideways > vertical * 1.5 { goBack() }
                }
        )
    }

    /// The app's own ink on the opening screen. It was `.primary`, on the
    /// reasoning that the button wanted to be black and that a literal black
    /// would not invert in the dark — true of `Color.black`, but `mainText` is
    /// an adaptive colour and inverts the same as `.primary` does. What was
    /// left was a pure black button on a warm off-white page, the one thing in
    /// the app drawn from outside its own palette.
    private var barFill: Color {
        if isFirstStep { return Color(.mainText) }
        return canContinue ? Self.actionBlue : Self.actionBlue.opacity(0.4)
    }

    /// One button, and only one. Skip moved into the header, where it stops
    /// reading as a second opinion about the thing directly above it.
    @ViewBuilder
    private var footer: some View {
        if current == .notifications {
            VStack(spacing: 10) {
                Button { advance() } label: {
                    Text("Turn on notifications")
                        .font(.headline)
                        .foregroundStyle(Color(.homeBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(Color(.mainText), in: Capsule())
                }
                .buttonStyle(.plain)

                Button { advance(requestingNotifications: false) } label: {
                    Text("Not now")
                        .font(.headline)
                        .foregroundStyle(Color(.mainText))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                advance()
            } label: {
                Text(footerTitle)
                    .font(.headline)
                    .foregroundStyle(isFirstStep ? Color(.homeBackground) : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(barFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canContinue)
            .animation(.easeInOut(duration: 0.2), value: canContinue)
        }
    }

    /// Softer than going forward. Both are steps, but one is a decision and the
    /// other is undoing one, and a back that lands as firmly as a Continue makes
    /// the two feel interchangeable.
    private func goBack() {
        guard step > 0 else { return }
        focusedField = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation { step -= 1 }
    }

    /// Both buttons come through here, so the feedback lives here too rather
    /// than being attached to each of them separately.
    private var footerTitle: String {
        current == .notifications ? "Turn on notifications" : "Continue"
    }

    private func advance(requestingNotifications: Bool = true) {
        focusedField = nil
        if current == .notifications {
            guard requestingNotifications else {
                completeOnboarding()
                return
            }
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                await MainActor.run { completeOnboarding() }
            }
            return
        }
        guard !isLastStep else {
            completeOnboarding()
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        step += 1
    }

    private func completeOnboarding() {
        // The end of the questions, not another step through them — the
        // heavier notification marks it as arriving somewhere.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        saveDraft()
        onContinue()
    }

    /// Everything but the trade, which already has its own key and its own
    /// adoption. Saved on the way out rather than as it's typed: half an answer
    /// isn't worth carrying into an account.
    private func saveDraft() {
        var draft = OnboardingDraft()
        let name = businessName.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.businessName = name.isEmpty ? nil : name
        if isTaxRegistered {
            let typed = Double(taxRate.replacingOccurrences(of: ",", with: "."))
            draft.taxRate = typed.map { max(0, $0) }
        }
        draft.rates = draftRates
        if draft.isEmpty { OnboardingDraft.clear() } else { draft.save() }
    }

    // MARK: - Step 2 · trade

    private var tradeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What's your trade?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))

            Text("So a quote knows that “20 mil” means your 20 mil.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // A grid of taps rather than a text field: this is answered once,
            // standing in a van, and a keyboard is the slowest way to say a
            // word the app could have offered.
            FlowLayout(spacing: 8) {
                ForEach(Self.trades, id: \.self) { trade in
                    let isOther = trade == Self.otherTrade
                    let picked = isOther ? isCustomTrade : (!isCustomTrade && pendingTrade == trade)
                    Button {
                        if isOther {
                            // The stored trade is whatever they type, not the
                            // word "Something else" — that string was being sent
                            // to the extraction as trade context, where it says
                            // less than nothing.
                            isCustomTrade = !isCustomTrade
                            pendingTrade = ""
                        } else {
                            isCustomTrade = false
                            pendingTrade = picked ? "" : trade
                        }
                    } label: {
                        Text(trade)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(picked ? .white : Color(.mainText))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(picked
                                        ? Self.actionBlue : Color(.cardSurface),
                                        in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(
                                    picked ? .clear : Color(.separator),
                                    lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: pendingTrade)
            .animation(.easeInOut(duration: 0.15), value: isCustomTrade)

            // Typed rather than tapped, because there is no list of every trade
            // there is. Whatever goes here reaches the extraction as context —
            // "Locksmith" tells it something, "Something else" tells it nothing.
            if isCustomTrade {
                TextField("Locksmith, glazier, welder…", text: $pendingTrade)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .customTrade)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.cardSurface),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Step 3 · the jobs they do

    /// Ticking, not typing. The point of this screen is that it can be answered
    /// while holding something in the other hand.
    private var jobsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Which of these\ndo you do?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            Text("Verbal prices these for you automatically when you quote them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            FlowLayout(spacing: 8) {
                ForEach(TradePresets.jobs(for: pendingTrade)) { job in
                    let picked = pickedJobs.contains(job.name)
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        if picked { pickedJobs.remove(job.name) } else { pickedJobs.insert(job.name) }
                    } label: {
                        Text(job.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(picked ? .white : Color(.mainText))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .background(picked ? Self.actionBlue : Color(.cardSurface),
                                        in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(picked ? .clear : Color(.separator),
                                                       lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: pickedJobs)
        }
    }

    // MARK: - Step 4 · what they charge

    /// Currency lives here rather than on a screen of its own: it is the same
    /// question as "what do you charge", asked in the same breath, and it is
    /// already answered from the device's region for most people.
    private var pricesStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Roughly what\ndo you charge?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            Text("A rough number beats none — you can correct any of them later.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(AppCurrency.allCases) { option in
                        Button {
                            currencyCode = option.rawValue
                        } label: {
                            Text("\(option.symbol) \(option.rawValue)")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(currencyCode == option.rawValue
                                                 ? .white : Color(.mainText))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(currencyCode == option.rawValue
                                            ? Self.actionBlue : Color(.cardSurface),
                                            in: Capsule())
                                .overlay(
                                    Capsule().strokeBorder(
                                        currencyCode == option.rawValue
                                            ? .clear : Color(.separator),
                                        lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
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
                    ForEach(pickedList) { job in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(job.name)
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(Color(.mainText))
                                    .lineLimit(1)
                                Text("per \(job.unit)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: 3) {
                                Text(AppCurrency.current.symbol)
                                    .foregroundStyle(.secondary)
                                TextField("0", text: Binding(
                                    get: { prices[job.name] ?? "" },
                                    set: { prices[job.name] = $0 }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focusedField, equals: .price(job.name))
                                .frame(width: 72)
                            }
                            .font(.callout.monospacedDigit())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Color(.cardSurface),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color(.separator), lineWidth: 0.5)
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: - Step 5 · the business

    private var businessStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What's your\nbusiness called?")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)

            // Asked here because the alternative is asking at the worst possible
            // moment: today the first attempt to share a quote stops to collect
            // this, with a customer waiting on the other end.
            Text("It goes at the top of every quote you send.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("e.g. Kapanadze Plumbing", text: $businessName)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .businessName)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.cardSurface),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )

            Toggle(isOn: $isTaxRegistered.animation(.easeInOut(duration: 0.2))) {
                Text("I'm tax registered")
                    .font(.callout)
                    .foregroundStyle(Color(.mainText))
            }
            .tint(Self.actionBlue)

            if isTaxRegistered {
                HStack(spacing: 8) {
                    Text("Rate")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("20", text: $taxRate)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.callout.monospacedDigit())
                        .focused($focusedField, equals: .taxRate)
                        .frame(width: 60)
                    Text("%").foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.cardSurface),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Step 6 · the reveal

    /// Their own answers, priced, before they have signed up for anything.
    ///
    /// Canned on purpose: a live recording here would need the microphone before
    /// the app has earned it, and a poor first extraction is a poor first
    /// impression. Everything on this card is real — their trade, their
    /// currency, the prices they just typed — it simply isn't spoken.
    private var revealStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(revealTitle)
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                Text(sampleSpokenLine)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Image(systemName: "arrow.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Self.actionBlue.opacity(0.5))
                    .frame(maxWidth: .infinity)

                LineItemsCard {
                    ForEach(Array(sampleLines.enumerated()), id: \.offset) { index, line in
                        if index > 0 { Divider() }
                        LineItemRow(description: line.name,
                                    quantityText: "\(line.quantity) \(line.unit)",
                                    isMissingPrice: line.price == nil,
                                    lineTotal: line.price,
                                    currencyCode: currencyCode)
                    }
                }
            }

            Text(draftRates.isEmpty
                 ? "Your rate card is a tab away whenever you want to fill it in."
                 : "Saved to your rate card. Speak a job and these fill themselves in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Notifications

    /// A permission request needs a reason before the system takes over. These
    /// examples are deliberately visit reminders — useful work the app already
    /// does — rather than vague promises about updates.
    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            notificationPreview
                .padding(.top, 16)

            Text("Never miss a\nvisit.")
                .font(.robotoSlab(32, relativeTo: .largeTitle))
                .foregroundStyle(Color(.mainText))
                .padding(.top, 34)

            Text("Get a reminder when it’s time to visit a customer and record their quote. You can change this anytime in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Spacer(minLength: 0)
        }
    }

    private var notificationPreview: some View {
        ZStack(alignment: .topTrailing) {
            previewNotification(icon: "calendar", tint: Color(.royalBlue100),
                                title: "Visit in 15 minutes",
                                message: "Bathroom re-tiling · Marina Kapanadze")
                .padding(.trailing, 12)

            previewNotification(icon: "mic.fill", tint: Color(.royalBlue25),
                                title: "Ready to record your quote",
                                message: "Turn the visit into a quote while it’s fresh")
                .padding(.top, 82)
                .padding(.leading, 20)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .padding(18)
        .background(Color(.fieldFill), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func previewNotification(icon: String, tint: Color, title: String, message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .foregroundStyle(Color(.mainText))
                .frame(width: 42, height: 42)
                .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(.mainText))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.cardSurface), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Step 1 · the app, running

    /// The first thing anyone sees: the real app, in a phone, before a single
    /// question is asked.
    ///
    /// Opening here rather than closing on it means the five questions that
    /// follow are answered by someone who has already seen what they are for.
    /// Asked cold they are a form; asked after this they are setup.
    ///
    /// The frame is here and the film isn't. Until it is, the glass holds a
    /// quote rather than a play button: a still of the thing itself says more
    /// than an icon promising one, and it is the real `LineItemsCard`, so it
    /// can't quietly stop resembling the app.
    ///
    /// The clip goes in the same seam. Drop a looping `VideoPlayer` (or an
    /// `AVPlayerLayer` wrapped in a `UIViewRepresentable`, muted, no controls)
    /// into `DevicePreview`'s content in place of `OnboardingPhoneScreen` — the
    /// screen is sized and positioned around whatever goes in there.
    ///
    /// Keep it short and silent. This plays before anyone has agreed to
    /// anything, so it can't ask for attention it hasn't earned, and a clip that
    /// outlasts its welcome is worse than no clip.
    /// The phone leads and the words follow it, centred — nothing is being
    /// asked yet, so the writing is a caption to the thing above it rather than
    /// a heading over it.
    private var videoStep: some View {
        VStack(spacing: 14) {
            DevicePreview {
                OnboardingPhoneScreen(currencyCode: currencyCode)
            }
            // Held to a share of the width rather than filling it. At full
            // width the phone crowded its own caption and reached for the
            // button, which made a screen with three things on it feel full.
            .frame(width: 264)
            .frame(maxWidth: .infinity)

            // The flexible gap settles the promise near the bottom without
            // competing with the phone preview above it.
            Spacer(minLength: 24)
                .frame(maxHeight: 72)

            // Keep the two-part promise centred as a unit, then leave a clear
            // beat before Continue so the message and its action do not read
            // as one crowded control.
            VStack(alignment: .center, spacing: 10) {
                onboardingPromiseLine("Speak it.", icon: "OnboardingSpeak")
                onboardingPromiseLine("Send it.", icon: "OnboardingSend")
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
    }

    private func onboardingPromiseLine(_ text: String, icon: String) -> some View {
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

    /// Skipping every question is a legitimate way through this, and the screen
    /// has to be honest about it: nothing was set up, so nothing claims to have
    /// been. It still shows what a spoken job turns into, which is the one thing
    /// worth knowing before signing in.
    private var revealTitle: String {
        return draftRates.isEmpty
            ? "This is what a job\nturns into."
            : "Your first quote is\nhalf-written already."
    }

    /// Two of their own rates and one they didn't price, so the sample shows
    /// both halves of what the app does — filling prices in, and flagging the
    /// ones nobody said. With nothing saved it falls back to the same example
    /// the first screen used, which is an illustration rather than a claim.
    private var sampleLines: [(name: String, quantity: Int, unit: String, price: Double?)] {
        guard !draftRates.isEmpty else {
            // Three, because the sentence above says three. A quantity that
            // contradicts the line it was supposedly extracted from undermines
            // the one thing this screen is demonstrating.
            return [
                (name: "Remove old toilet and fit new toilet", quantity: 1,
                 unit: "each", price: 90),
                (name: "Mixer taps", quantity: 3, unit: "each", price: nil),
            ]
        }
        var lines = draftRates.prefix(2).map {
            (name: $0.name, quantity: 1, unit: $0.unit, price: Optional($0.price))
        }
        lines.append((name: "Materials from the supplier", quantity: 1,
                      unit: "job", price: nil))
        return lines
    }

    private var sampleSpokenLine: String {
        guard let first = draftRates.first else {
            return "“Replace the toilet, ninety. Three mixer taps.”"
        }
        return "“\(first.name.lowercased()), and the materials from the supplier — I'll price those tomorrow.”"
    }
}

// The whole flow runs before there is an account, so it previews on its own —
// no session, no network, nothing to sign into.
//
// The trade is stored in `UserDefaults`, which the canvas shares with whatever
// ran last, so each preview sets it explicitly rather than inheriting a chip
// somebody tapped an hour ago. Setting it also decides which steps exist: a
// trade with presets is a six-screen run, no trade is four.
#Preview("From the start") {
    UserDefaults.standard.removeObject(forKey: "pendingTrade")
    return OnboardingView(onContinue: {})
}

#Preview("Trade already picked") {
    UserDefaults.standard.set("Plumber", forKey: "pendingTrade")
    return OnboardingView(onContinue: {})
}
