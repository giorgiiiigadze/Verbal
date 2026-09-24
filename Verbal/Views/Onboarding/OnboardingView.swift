//
//  OnboardingView.swift
//  Verbal
//
//  The screens after registering and before entering the app.
//
//  Three acts rather than a queue of questions. The introduction names the
//  problem and prices it in the user's own numbers; the climax hands them the
//  app and lets them make a quote by speaking; the conclusion says what they
//  came for, what it costs, and how the
//  reminders keep it happening.
//
//  It is longer than it was, on purpose. The setup questions were always here —
//  answered cold they are a form, and answered after someone has watched what
//  quoting costs them in a year they are the first thing being done about it.
//
//  It runs after authentication. Answers stay local while it is in progress,
//  then are written to the newly authenticated profile at completion.
//

import SwiftUI

struct OnboardingView: View {
    /// Called when the last step is finished, to hand over to the auth screen.
    var onContinue: () -> Void

    @Environment(SessionStore.self) private var session
    @State private var model = OnboardingModel()
    @State private var step = 0
    @FocusState private var focusedField: OnboardingField?
    @State private var isTradeHeaderSeparated = false
    @State private var isTradeFooterSeparated = false
    /// A short handoff after the final choice gives setup a visible finish
    /// before the main app appears.
    @State private var isPreparing = false
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

    var body: some View {
        Group {
            if isPreparing {
                OnboardingPreparationView(onFinished: onContinue)
                    .transition(.opacity)
            } else {
                NavigationStack {
                    content
                    .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if step > 0 {
                            Button {
                                goBack()
                            } label: {
                                Image(systemName: "chevron.backward")
                            }
                            .accessibilityLabel("Back")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { completeOnboarding() }
                    }
                }
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var content: some View {
        ZStack {
            Color(red: 252 / 255, green: 252 / 255, blue: 249 / 255)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    stepView
                }
                // Each step arrives from the side it was going, so the sequence
                // reads as forward motion rather than as unrelated
                // screens sharing a background.
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 24)),
                    removal: .opacity.combined(with: .offset(x: -24))
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            // Less than the sides: the home indicator already reserves space
            // below this, and matching 24 to it left the button floating well
            // clear of the bottom of the screen.
            .padding(.bottom, 8)
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    @ViewBuilder
    private var stepView: some View {
        switch current {
        case .welcome:
            OnboardingFeatureStep(feature: .welcome)
        case .speak:
            OnboardingFeatureStep(feature: .speak)
        case .quote:
            OnboardingFeatureStep(feature: .quote)
        case .organise:
            OnboardingFeatureStep(feature: .organise)
        case .followUp:
            OnboardingFeatureStep(feature: .followUp)
        case .businessName:
            OnboardingBusinessNameStep(model: model, focused: $focusedField)
        case .trade:
            OnboardingTradeStep(
                model: model,
                focused: $focusedField,
                isProgressHeaderSeparated: $isTradeHeaderSeparated,
                isFooterSeparated: $isTradeFooterSeparated
            )
        }
    }

    // MARK: - The button

    private var footer: some View {
        Button { advance() } label: {
            Text(isLastStep ? "Get started" : "Continue")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.black, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canAdvance)
        .opacity(canAdvance ? 1 : 0.45)
    }

    private var canAdvance: Bool {
        switch current {
        case .businessName:
            !model.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .trade:
            !model.trade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            true
        }
    }

    // MARK: - Moving

    private func goBack() {
        guard step > 0 else { return }
        focusedField = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation {
            step -= 1
        }
    }

    private func advance() {
        guard canAdvance else { return }
        guard !isLastStep else {
            completeOnboarding()
            return
        }
        focusedField = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation {
            step += 1
        }
    }

    private func completeOnboarding() {
        guard !isPreparing else { return }
        // The end of the questions, not another step through them — the
        // heavier notification marks it as arriving somewhere.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        model.saveDraft()
        Task { await session.adoptPostAuthOnboarding() }
        withAnimation(.easeInOut(duration: 0.25)) {
            isPreparing = true
        }
    }
}

// The preview supplies its own session store because the real flow now follows
// authentication.
//
// The trade is stored in `UserDefaults`, which the canvas shares with whatever
// ran last, so each preview sets it explicitly rather than inheriting a chip
// somebody tapped an hour ago. Setting it also decides which steps exist.
#Preview("From the start") {
    UserDefaults.standard.removeObject(forKey: "pendingTrade")
    return OnboardingView(onContinue: {})
        .environment(Store())
}
