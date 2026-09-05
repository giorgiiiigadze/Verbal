//
//  OnboardingView.swift
//  Verbal
//
//  The screens between installing the app and signing in.
//
//  Three acts rather than a queue of questions. The introduction names the
//  problem and prices it in the user's own numbers; the climax hands them the
//  app and lets them make a quote by speaking, before anyone has signed up for
//  anything; the conclusion says what they came for, what it costs, and how the
//  reminders keep it happening.
//
//  It is longer than it was, on purpose. The setup questions were always here —
//  answered cold they are a form, and answered after someone has watched what
//  quoting costs them in a year they are the first thing being done about it.
//
//  It all runs before auth, so there is no user to save anything to. The
//  answers are held on the device and written to the profile on first sign-in.
//

import StoreKit
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    /// Called when the last step is finished, to hand over to the auth screen.
    var onContinue: () -> Void

    @AppStorage("mainCurrency") private var currencyCode = AppCurrency.deviceDefault.rawValue

    @Environment(Store.self) private var store
    @Environment(\.requestReview) private var requestReview

    @State private var model = OnboardingModel()
    @State private var step = 0
    /// The route can grow when someone chooses a trade with preset jobs. Keep
    /// the visible bar tied to navigation, not to an answer changing beneath
    /// the current screen.
    @State private var displayedProgress = 0.0
    @FocusState private var focusedField: OnboardingField?

    private typealias Step = OnboardingModel.Step

    /// Clamped, because `steps` shrinks underneath the index when someone swipes
    /// back and unticks every job.
    private var current: Step {
        let all = model.steps
        return all[min(step, all.count - 1)]
    }

    /// Asked of the list rather than compared against one case, so adding a
    /// screen to the end doesn't leave the finishing behaviour on the one
    /// before it.
    private var isLastStep: Bool { step >= model.steps.count - 1 }

    /// The opening screen, which carries the invitation into all this. Every
    /// screen after it is a step through it.
    private var isFirstStep: Bool { step == 0 }

    /// The trade is the one answer with no sensible default, and it reaches the
    /// extraction on every quote. So it is the one question that is asked
    /// rather than offered — everything else here has a default worth keeping,
    /// or is not a question at all.
    ///
    /// The recording screen is the other gate, and a softer one: Continue waits
    /// until there is something to carry forward, and Skip in the header is
    /// always there for someone who would rather not talk to their phone in
    /// front of a customer.
    private var canContinue: Bool {
        switch current {
        case .method:
            return model.answers.method != nil
        case .quoteVolume:
            return model.answers.quotesPerWeek != nil
        case .quoteDuration:
            return model.answers.minutesPerQuote != nil
        case .trade:
            return !model.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .jobs:
            return !model.pickedJobs.isEmpty
        case .record:
            return !model.recorder.isSessionActive && model.recorder.hasContent
        case .commitment:
            return model.answers.commitment != nil
        default:
            return true
        }
    }

    /// Steps a Skip button belongs on: the ones that collect something the app
    /// can manage without. Never on a statement screen, where there is nothing
    /// to skip and the button would just be a second Continue.
    private var isSkippable: Bool {
        switch current {
        case .method, .quoteVolume, .quoteDuration, .jobs, .prices, .business, .micReason, .record:
            return true
        default:
            return false
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
                        // preview, its promise and Continue. The app name
                        // returns with the questions.
                        if !isFirstStep {
                            HStack(spacing: 8) {
                                Image(.brandMark)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20)
                                    .foregroundStyle(OnboardingStyle.action)
                                Text("Verbal")
                                    .font(.robotoSlab(18, relativeTo: .headline))
                                    .foregroundStyle(OnboardingStyle.action)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // Never a wall: every question has a sensible answer
                        // already, and nobody should be stuck on the way to the
                        // thing they installed the app for.
                        if isSkippable {
                            Button("Skip") { skip() }
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
        // Loaded here rather than on the screen that shows the price: StoreKit
        // takes a moment, and a number that appears after the screen does reads
        // as the app changing its mind about what it charges.
        .task { await store.loadProducts() }
    }

    private var content: some View {
        ZStack {
            // Plain ground. These screens ask a dozen questions and show a
            // quote, and drawn waves behind a form is decoration competing with
            // the thing being read. The illustration stays on sign-in, where
            // there is nothing to answer and it is the whole of the welcome —
            // so arriving there now reads as the app opening rather than as
            // more of the same.
            Color(.homeBackground).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Eighteen screens is long enough that "how much more of this"
                // is a fair question, and a hairline answers it without
                // inviting anyone to stop and count.
                if !isFirstStep {
                    OnboardingProgressBar(progress: progress)
                        .padding(.bottom, 20)
                        .transition(.opacity)
                }

                Group {
                    stepView
                }
                // Each step arrives from the side it was going, so the sequence
                // reads as forward motion rather than as eighteen unrelated
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
                    guard step > 0, !model.recorder.isSessionActive else { return }
                    let sideways = drag.translation.width
                    let vertical = abs(drag.translation.height)
                    // Through the same path as the button, so a swipe back and
                    // a tap back feel like the one action they are.
                    if sideways > 60, sideways > vertical * 1.5 { goBack() }
                }
        )
    }

    @ViewBuilder
    private var stepView: some View {
        switch current {
        case .hook:
            OnboardingHookStep(currencyCode: currencyCode)
        case .method:
            OnboardingMethodStep(model: model)
        case .quoteVolume:
            OnboardingQuoteVolumeStep(model: model)
        case .quoteDuration:
            OnboardingQuoteDurationStep(model: model)
        case .stat:
            OnboardingStatStep(answers: model.answers)
        case .trade:
            OnboardingTradeStep(model: model, focused: $focusedField)
        case .jobs:
            OnboardingJobsStep(model: model)
        case .prices:
            OnboardingPricesStep(model: model, currencyCode: $currencyCode,
                                 focused: $focusedField)
        case .business:
            OnboardingBusinessStep(model: model, focused: $focusedField)
        case .summary:
            OnboardingSummaryStep(model: model)
        case .micReason:
            OnboardingMicReasonStep()
        case .record:
            OnboardingRecordStep(model: model)
        case .result:
            OnboardingResultStep(model: model, currencyCode: currencyCode)
        case .milestone:
            OnboardingMilestoneStep(model: model)
        case .review:
            OnboardingReviewStep()
        case .goal:
            OnboardingGoalStep(answers: model.answers)
        case .commitment:
            OnboardingCommitmentStep(model: model)
        case .expectations:
            OnboardingExpectationsStep(
                answers: model.answers,
                monthlyPrice: store.monthly.map { NSDecimalNumber(decimal: $0.price).doubleValue },
                monthlyDisplayPrice: store.monthly?.displayPrice
            )
        case .notifications:
            OnboardingNotificationsStep()
        }
    }

    private var progress: Double {
        displayedProgress
    }

    private func progress(at index: Int) -> Double {
        let all = model.steps
        guard all.count > 1 else { return 1 }
        return Double(min(index, all.count - 1)) / Double(all.count - 1)
    }

    private func updateDisplayedProgress() {
        displayedProgress = progress(at: step)
    }

    // MARK: - The button

    /// The app's own ink on the opening screen. It was `.primary`, on the
    /// reasoning that the button wanted to be black and that a literal black
    /// would not invert in the dark — true of `Color.black`, but `mainText` is
    /// an adaptive colour and inverts the same as `.primary` does. What was
    /// left was a pure black button on a warm off-white page, the one thing in
    /// the app drawn from outside its own palette.
    private var barFill: Color {
        if isFirstStep { return Color(.mainText) }
        return canContinue ? OnboardingStyle.action : OnboardingStyle.action.opacity(0.4)
    }

    /// One button, and only one, except on the two screens that ask iOS for
    /// something. There a plain Continue would be a trick — the button that
    /// raises a system dialog has to say so, and the way out has to sit beside
    /// it rather than hide in the header.
    @ViewBuilder
    private var footer: some View {
        switch current {
        case .notifications:
            pairedFooter(primary: "Turn on notifications",
                         secondary: "Not now") { wantsNotifications in
                finish(requestingNotifications: wantsNotifications)
            }
        case .review:
            pairedFooter(primary: "Rate Verbal", secondary: "Not now") { wantsReview in
                if wantsReview { requestReview() }
                advance()
            }
        default:
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

    private func pairedFooter(primary: String, secondary: String,
                              action: @escaping (Bool) -> Void) -> some View {
        VStack(spacing: 10) {
            Button { action(true) } label: {
                Text(primary)
                    .font(.headline)
                    .foregroundStyle(Color(.homeBackground))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(Color(.mainText), in: Capsule())
            }
            .buttonStyle(.plain)

            Button { action(false) } label: {
                Text(secondary)
                    .font(.headline)
                    .foregroundStyle(Color(.mainText))
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var footerTitle: String {
        switch current {
        case .hook: return "Get started"
        case .record: return model.recorder.hasContent ? "That's the one" : "Continue"
        case .result: return "Nice"
        default: return "Continue"
        }
    }

    // MARK: - Moving

    /// Softer than going forward. Both are steps, but one is a decision and the
    /// other is undoing one, and a back that lands as firmly as a Continue makes
    /// the two feel interchangeable.
    private func goBack() {
        guard step > 0 else { return }
        focusedField = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation {
            step -= 1
            updateDisplayedProgress()
        }
    }

    private func advance() {
        focusedField = nil
        guard !isLastStep else {
            finish(requestingNotifications: false)
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            step += 1
            updateDisplayedProgress()
        }
    }

    /// Skipping the microphone explanation skips the recording too — the two
    /// are one decision, and dropping someone who just declined the explanation
    /// onto a record button is the app asking again in a worse way.
    private func skip() {
        focusedField = nil
        if current == .micReason {
            let all = model.steps
            if let resumeAt = all.firstIndex(of: .result) {
                withAnimation {
                    step = resumeAt
                    updateDisplayedProgress()
                }
                return
            }
        }
        advance()
    }

    private func finish(requestingNotifications: Bool) {
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
    }

    private func completeOnboarding() {
        // The end of the questions, not another step through them — the
        // heavier notification marks it as arriving somewhere.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        model.saveDraft()
        onContinue()
    }
}

// The whole flow runs before there is an account, so it previews on its own —
// no session, no network, nothing to sign into.
//
// The trade is stored in `UserDefaults`, which the canvas shares with whatever
// ran last, so each preview sets it explicitly rather than inheriting a chip
// somebody tapped an hour ago. Setting it also decides which steps exist.
#Preview("From the start") {
    UserDefaults.standard.removeObject(forKey: "pendingTrade")
    return OnboardingView(onContinue: {})
        .environment(Store())
}
